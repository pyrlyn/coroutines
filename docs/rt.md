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
  fields; the runtime never allocates a stack. `rt.Seq` (below) writes the
  state machine for you from a list of steps.

## API

| item | what it does |
|---|---|
| `Runtime.init(*Runtime, gpa, io, Options)` / `deinit` | start / stop the workers; `gpa` must be thread-safe; the runtime must not move |
| `Options` | `workers` (0 = CPUs), `current_thread` (no threads; `blockOn` drives the scheduler), `stack_size`, `spin_rounds`, `monitor_interval_ns` (stuck-worker check once the driver is running, default 1 ms, 0 = off) |
| `Runtime.blockOn(T, task) !T.Output` | run a root task to completion from a plain thread |
| `Runtime.spawn(T, task) !JoinHandle(T)` / `spawnDetached` | spawn from anywhere (a task of this runtime: its worker's queue; elsewhere: the injector) |
| `JoinHandle(T).poll(cx)` | wait for the result (`error.Canceled` after `abort`); `tryResult`, `isFinished`, `abort`, `deinit` (detach) |
| `Context.waker()` → `Waker` | wake a task from anywhere (`wake`, `wakeByRef`, `clone`, `deinit`) |
| `Context.yieldNow()` | requeue behind other ready tasks |
| `Channel(T)` | bounded MPMC over caller storage (`buf.len == 0` = rendezvous): `send`, `recv`, `trySend`, `tryRecv`, `close`, `cancelSend`, `cancelRecv` |
| `Semaphore` | FIFO counting semaphore (concurrency limits, backpressure): `acquire`, `tryAcquire`, `release`, `cancel` |
| `Runtime.liveTasks()` | live task frames (debug builds; for leak checks) |
| `Runtime.now()` | ns on the monotonic clock that timers use |
| `Timer` | one-shot timer embedded in a task: `sleepUntil(cx, deadline)`, `sleep(cx, ns)`, `cancel`, `isArmed` |
| `Sleep` | a task that is ready after `ns` (`Sleep.init(ns)`) |
| `Channel.recvDeadline` / `sendDeadline`, `Semaphore.acquireDeadline`, `JoinHandle.pollDeadline` | the same waits with a deadline; `error.Timeout` when it passes (a join that times out leaves the task running and the handle valid) |
| `IoSource` | readiness I/O on a non-blocking fd (sockets, pipes, ttys): `register`, `read`, `write`, `readable`, `writable`, `cancelWaits`, `deregister` |
| `Blocking(Ctx, Out, func)` / `FileRead` | run a blocking call on the blocking pool; `FileRead` is `pread` of a regular file |
| `Seq(Ctx)` | a task from a list of steps (`Ctx.steps`), each returning a `Flow`: `.pending`, `.next`, `.{ .jump = i }`, `.done`; `rt.into` stores a ready value |
| `Race(A, B)` / `All(A, B)` | run two tasks inside one task: first to finish (the loser's `deinit` runs) / both |
| `Runtime.monitorRescues()` | how often the monitor made a stuck worker's tasks stealable |

`Channel.send` / `recv` and `Semaphore.acquire` take a waiter that lives in the
task (`Channel(T).SendWaiter`, `RecvWaiter`, `Semaphore.Waiter`); pass the same
one on every poll until the call is ready. Waiting allocates nothing.

### Timers, I/O and blocking work

```zig
const WithTimeout = struct {
    pub const Output = error{Timeout}!?u32;
    ch: *rt.Channel(u32),
    w: rt.Channel(u32).RecvWaiter = .{},
    t: rt.Timer = .{},
    deadline: u64 = 0,
    pub fn poll(self: *WithTimeout, cx: *rt.Context) rt.Poll(Output) {
        if (self.deadline == 0) self.deadline = cx.runtime().now() + 50 * std.time.ns_per_ms;
        return self.ch.recvDeadline(cx, &self.w, &self.t, self.deadline);
    }
    pub fn deinit(self: *WithTimeout) void { // when aborted
        _ = self.t.cancel();
        self.ch.cancelRecv(&self.w);
    }
};
```

* **Driver thread.** Each runtime has at most one driver thread. It starts
  lazily, on the first timer or `IoSource` (the same on `current_thread` and
  on a worker pool). Until then there is no extra thread, and the worker hot
  path does not touch the monitor. The driver owns the timers and the OS
  poller. It wakes tasks through the normal wake path: injector, then a
  parked worker.
* **Timers** are intrusive nodes of a pairing heap. Arming one allocates
  nothing, and the earliest deadline is exact. The driver sleeps in the poller
  until that deadline. Nothing busy-waits. A new earlier deadline pokes it.
  Precision is that of the OS sleep: about 1 ms on Linux with `epoll`, finer
  with `kqueue`.
* **Reactor.** `kqueue` on macOS and the BSDs (with `EVFILT_USER` to poke).
  `epoll`, edge-triggered, on Linux (with an `eventfd`). `IoSource.read` and
  `write` try the syscall first and wait for readiness only on `WouldBlock`.
  **Windows has no reactor yet** (no IOCP): `IoSource.register` returns
  `error.Unsupported`, while timers and the blocking pool work.
  **io_uring is not used.** It would add a completion-based path next to the
  readiness one, so readiness is shared by both Unix OSes.
* **Files.** Regular files are always "ready" to `kqueue` and `epoll`, so
  readiness cannot make them asynchronous. `FileRead` (and any
  `Blocking(Ctx, Out, func)`) runs the call on a lazily started blocking pool
  of up to 16 threads and wakes the task when it returns. This is a thread
  doing a blocking `pread`, not asynchronous file I/O. `Runtime.deinit` waits
  for running operations.
* **Monitor.** Once the driver is running, while some worker is awake it
  checks every `monitor_interval_ns`. A worker can stay inside the same poll
  while it holds unpublished queue tasks (up to 7). The driver then publishes
  that tail and wakes a parked worker to steal them — the same idea as Go's
  sysmon, minus preemption. The LIFO slot stays local, as in tokio, so
  ping-pong and spawn+join do not pay an atomic on the wake path. `poll_seq`
  (a stuck-poll counter) is only stored after the driver has started.

### `Seq`, `Race`, `All`

```zig
const PingPong = rt.Seq(struct {
    pub const Output = u64;
    pub const steps = .{ send, recv };
    to: *rt.Channel(u64), from: *rt.Channel(u64), n: u64, i: u64 = 0, got: ?u64 = null,
    sw: rt.Channel(u64).SendWaiter = .{}, rw: rt.Channel(u64).RecvWaiter = .{},
    const C = @This();
    pub fn output(c: *C) u64 { return c.i; }
    fn send(c: *C, cx: *rt.Context) rt.Flow {
        if (c.i == c.n) return .done;
        return if (c.to.send(cx, &c.sw, c.i) == .pending) .pending else .next;
    }
    fn recv(c: *C, cx: *rt.Context) rt.Flow {
        if (rt.into(?u64, c.from.recv(cx, &c.rw), &c.got) == .pending) return .pending;
        c.i += 1;
        return .{ .jump = 0 };
    }
});
// r.blockOn(PingPong, .init(.{ .to = &a, .from = &b, .n = 1000 }))
```

`Seq` dispatches with an `inline` switch over the step index. Each step is a
direct call that the compiler can inline, so the code is the same as a
hand-written `switch (state)`. There is no function pointer and no allocation,
and the frame grows by one byte. The benchmarks run spawn + join and ping-pong
both ways: `spawnjoin1seq_*` and `pingpongseq_*`. The trade-off is the one
every stackless design has. A value that must survive a wait lives in the
context struct, not in a local variable.

A stackful mode (one stack per task, `await` anywhere) would need a stack per
task (KiBs instead of a 64 B frame) and a context switch per wait, so it is
not offered. `coroutines.evented` already gives that model on `Io.Evented`.

`Race(A, B)` polls both tasks in the same task. They share one waker, so
nothing extra is spawned. The loser's `deinit` runs as soon as the winner is
ready. `Race(T, rt.Sleep)` is a timeout for any task. `All(A, B)` waits for
both.

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

* Tasks are state machines, written by hand or with `Seq`. There is no
  `async`/`await` sugar in Zig 0.17.
* The LIFO slot is not stealable. Up to 7 unpublished tasks stay invisible to
  thieves until the poll returns, or — once the driver is running — until the
  monitor publishes them (1–2 `monitor_interval_ns` into a long poll). A task
  that spawns work and then computes for a long time is still better off
  calling `yieldNow` first.
* The reactor is readiness-based (`kqueue`/`epoll`). Windows has timers and
  the blocking pool but no socket reactor. File I/O goes through the blocking
  pool.
* There is at most one driver thread per runtime, started on the first timer
  or `IoSource`. A timer fired or a readiness event costs a cross-thread wake:
  injector, then futex, on the order of microseconds. tokio's workers poll the
  driver themselves. This design keeps the worker hot path free of driver
  checks until that first timer or I/O wait.
* `deinit` drops tasks that are still pending without running their `deinit`
  (their frames are freed with the slabs).

## Benchmarks

`zig build bench-rt` (ReleaseFast) runs the workloads of
[`bench/rt.zig`](../bench/rt.zig): yield switch, spawn + join one task at a
time, spawn 1M then join all, channel ping-pong (capacity 1), fan-out / fan-in
of 200k senders through a 1024-slot channel, and a skewed CPU load (1 % of
10k tasks are 100× heavier). Equivalent tokio and Go programs and the results
are in [`bench/results/rt-vs-tokio-go-darwin-arm64.md`](../bench/results/rt-vs-tokio-go-darwin-arm64.md).
