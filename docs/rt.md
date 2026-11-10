# `coroutines.rt` — work-stealing runtime for stackless tasks

`rt` is the library's own scheduler. Tasks are stackless state machines that
can **wait without holding a thread**: a task that waits for a join, a channel
or a semaphore returns `.pending` and costs nothing until it is woken. The
runtime uses `std.Io` only to park idle threads (futex), so it behaves the same
on every OS and does not depend on `Io.Evented`.

## Tasks

A task is any struct with an `Output` type and a `poll` function:

```zig
const rt = @import("coroutines").rt;

const Double = struct {
    pub const Output = u64;
    v: u64,
    pub fn poll(self: *Double, cx: *rt.Context) rt.Poll(u64) {
        _ = cx;
        return .{ .ready = self.v * 2 };
    }
};

/// Spawns a child and waits for it (the parent's state lives in its fields).
const Parent = struct {
    pub const Output = u64;
    h: ?rt.JoinHandle(Double) = null,
    pub fn poll(self: *Parent, cx: *rt.Context) rt.Poll(u64) {
        if (self.h == null) self.h = cx.runtime().spawn(Double, .{ .v = 21 }) catch @panic("oom");
        return switch (self.h.?.poll(cx)) {
            .pending => .pending,
            .ready => |r| .{ .ready = r catch 0 },
        };
    }
};

var r: rt.Runtime = undefined;
try r.init(gpa, io, .{}); // .{ .current_thread = true } for a single-thread runtime
defer r.deinit();
const v = try r.blockOn(Parent, .{}); // 42
```

* `poll` returns `.{ .ready = value }` or `.pending`. Return `.pending` only
  after registering interest in something that will wake the task (a
  `JoinHandle`, `Channel`, `Semaphore`, or a `Waker` you handed out), or after
  `cx.yieldNow()`.
* Optional `pub fn deinit(self: *T) void` runs once, after the last poll or when
  the task is aborted. A task that can be aborted while waiting must withdraw
  its waiters there (`Channel.cancelRecv` / `cancelSend`, `Semaphore.cancel`).
* Zig has no `async` functions in 0.17, so a task keeps its progress in its own
  fields; the runtime never allocates a stack.

## API

| item | what it does |
|---|---|
| `Runtime.init(*Runtime, gpa, io, Options)` / `deinit` | start / stop the workers; `gpa` must be thread-safe; the runtime must not move |
| `Options` | `workers` (0 = CPUs), `current_thread` (no threads; `blockOn` drives the scheduler), `stack_size`, `spin_rounds` |
| `Runtime.blockOn(T, task) !T.Output` | run a root task to completion from a plain thread |
| `Runtime.spawn(T, task) !JoinHandle(T)` / `spawnDetached` | spawn from anywhere (a task of this runtime: its worker's queue; elsewhere: the injector) |
| `JoinHandle(T).poll(cx)` | wait for the result (`error.Canceled` after `abort`); `tryResult`, `isFinished`, `abort`, `deinit` (detach) |
| `Context.waker()` → `Waker` | wake a task from anywhere (`wake`, `wakeByRef`, `clone`, `deinit`) |
| `Context.yieldNow()` | requeue behind other ready tasks |
| `Channel(T)` | bounded MPMC over caller storage (`buf.len == 0` = rendezvous): `send`, `recv`, `trySend`, `tryRecv`, `close`, `cancelSend`, `cancelRecv` |
| `Semaphore` | FIFO counting semaphore (concurrency limits, backpressure): `acquire`, `tryAcquire`, `release`, `cancel` |
| `Runtime.liveTasks()` | live task frames (debug builds; for leak checks) |

`Channel.send` / `recv` and `Semaphore.acquire` take a waiter that lives in the
task (`Channel(T).SendWaiter`, `RecvWaiter`, `Semaphore.Waiter`); pass the same
one on every poll until the call is ready. Waiting allocates nothing.

## Scheduler

The design is the one tokio and Go use, written for stackless Zig tasks:

* **Persistent workers.** `init` starts the threads once. An idle worker spins
  for `spin_rounds`, then parks on a futex. At most half of the workers search
  for work at a time; a searcher that finds work wakes the next one.
* **Per-worker run queue** (256 slots, FIFO for the owner, so `yieldNow`
  really yields). Thieves take **half** of a random victim's queue with one
  CAS. A full queue moves half of itself to the shared **injector**, which also
  takes tasks spawned from outside the runtime; workers check it every 61 ticks.
* **Private tail.** The owner publishes its queue tail in batches of 8 (and
  after each poll) and checks room against a cached thief index, so a spawn
  loop touches no cache line other workers write.
* **LIFO slot.** A task woken by the running task runs next on the same worker
  (at most 3 in a row before it goes to the queue). Channel ping-pong and
  spawn + join therefore never leave the core and never wake another thread.
* **Lazy notification.** A lone spawned task does not wake a parked worker: in
  spawn + join it is run by the same worker as soon as the parent waits. Two or
  more queued tasks, or a displaced LIFO task, wake one.
* **Task frames** (header + task, then the result in the same bytes) come from
  per-worker free lists in size classes (64 B … 4 KiB) backed by 64 KiB slabs.
  A spawn allocates nothing in steady state; larger tasks use `gpa` directly.
* **Channels and semaphores** hand values and permits straight to the oldest
  waiter and wake it under the lock; the woken task reads its result without
  taking the lock again.

### Trade-offs

* Tasks are hand-written state machines: no `async`/`await` sugar in Zig 0.17.
* The LIFO slot is not stealable, and up to 7 tasks spawned during one long
  poll stay invisible to thieves until that poll returns. A task that spawns
  work and then computes for a long time should `yieldNow` first.
* No timers or I/O reactor yet: tasks are woken by joins, channels, semaphores
  or `Waker`s (which plain threads, e.g. blocking I/O threads, can call).
* `deinit` drops tasks that are still pending without running their `deinit`
  (their frames are freed with the slabs).

## Benchmarks

`zig build bench-rt` (ReleaseFast) runs the workloads of
[`bench/rt.zig`](../bench/rt.zig): yield switch, spawn + join one task at a
time, spawn 1M then join all, channel ping-pong (capacity 1), fan-out / fan-in
of 200k senders through a 1024-slot channel, and a skewed CPU load (1 % of
10k tasks are 100× heavier). Equivalent tokio and Go programs and the results
are in [`bench/results/rt-vs-tokio-go-darwin-arm64.md`](../bench/results/rt-vs-tokio-go-darwin-arm64.md).
