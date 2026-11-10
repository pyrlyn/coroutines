# `rt` vs tokio vs Go — Apple M3 Max (12P+4E), macOS 27, 2026-11-10 08:42–08:45 EET

* pyrlyn `rt` (this PR), Zig 0.17.1 ReleaseFast. "before" = the same workloads on
  `main` with `std.Io.Threaded` (`concurrent`/`Group.async`/`Io.Queue`;
  [`compare/before`](../compare/before/src/main.zig)).
* tokio 1.54.1 (rustc 1.99.1, release, lto=fat, codegen-units=1); Go 1.27.1.
* Single-thread = `current_thread` / `new_current_thread()` / `GOMAXPROCS=1`;
  multi-thread = 16 workers / tokio default (16) / `GOMAXPROCS=16`.
* 7 fresh-process runs per binary in ABBA order (A B B A A B B; A = rt first),
  median with min–max. Allocations are counted by a wrapping allocator
  (Zig, Rust) or `runtime.MemStats` (Go).
* **Load:** the Mac was shared with other jobs, load average 19–29 during the
  run (`load` lines in the raw log). Absolute numbers are noisy; every program
  ran under the same conditions, interleaved.
* Workloads ([`bench/rt.zig`](../rt.zig), [`tokio`](../compare/tokio/src/main.rs),
  [`go`](../compare/go/main.go)): spawn + join one task at a time (200k);
  spawn 1M tasks, keep the handles, then join all; ping-pong over two
  capacity-1 channels (100k round trips); fan-out of 200k senders into one
  1024-slot channel, fan-in in the root; skewed CPU work (10k tasks, 1 % are
  100× heavier, an LCG loop); two tasks yielding to each other (20M switches).

## ns per operation, median (min–max)

| workload | threads | pyrlyn before (Io.Threaded) | **pyrlyn rt** | tokio | Go | winner |
|---|---|---:|---:|---:|---:|---|
| spawn + join one | 1 | — | **21.5** (21.0–22.4) | 100.8 (96.7–106.1) | 212.5 (202.5–225.8) | rt, 4.7× vs tokio |
| spawn + join one | 16 | 4053 | **22.0** (21.2–24.5) | 143.4 (137.0–167.6) | 253.5 (228.6–294.9) | rt, 6.5× vs tokio |
| spawn 1M, join all | 1 | — | **43.0** (40.1–49.7) | 88.4 (85.1–92.5) | 472.6 (447.3–492.5) | rt, 2.1× vs tokio |
| spawn 1M, join all | 16 | 1630 | **49.2** (42.5–57.2) | 208.6 (198.5–245.1) | 320.7 (210.0–359.5) | rt, 4.2× vs tokio |
| channel ping-pong | 1 | — | **24.6** (24.1–27.1) | 83.1 (77.9–95.9) | 190.4 (185.1–207.4) | rt, 3.4× vs tokio |
| channel ping-pong | 16 | 4063 | **25.0** (24.0–27.3) | 126.8 (119.1–136.1) | 234.0 (208.3–270.2) | rt, 5.1× vs tokio |
| fan-out / fan-in | 1 | — | **85.7** (77.9–94.0) | 148.6 (139.3–155.9) | 1816 (1465–2122) | rt, 1.7× vs tokio |
| fan-out / fan-in | 16 | 58105 | **183.4** (131.6–216.2) | 760.8 (712.3–799.6) | 755.1 (704.9–801.8) | rt, 4.1× vs Go |
| skewed CPU work | 1 | — | **1666** (1647–1736) | 1786 (1695–1877) | 2734 (2484–3309) | rt, 1.07× (compute-bound) |
| skewed CPU work | 16 | 3293 | **148.6** (139.2–192.3) | 323.3 (301.3–404.4) | 352.0 (319.3–412.0) | rt, 2.2× vs tokio |
| yield switch | 1 | — | **8.2** (7.9–8.7) | 50.0 (48.8–51.2) | 47.1 (45.8–56.8) | rt, 5.8× vs Go |
| yield switch | 16 | — | **7.6** (6.8–10.3) | 140.4 (127.8–187.7) | 110.5 (103.5–115.8) | rt, 14.5× vs Go |

Allocations per spawn: rt 0.001 (one 64 KiB slab per 1024 frames, reused
afterwards; 64 B frames), tokio 1.0 (128–153 B), Go 2.0 (40–72 B).

## Why, and caveats

* Spawn + join and ping-pong never leave the worker: the woken task goes to the
  LIFO slot and a lone spawned task wakes no other thread. tokio has a LIFO
  slot too, but each spawn allocates and the spawner notifies a parked worker.
* Spawn throughput on 16 threads comes from the private queue tail (published
  every 8 pushes) and pooled frames: the spawner touches no shared cache line
  per task.
* Skewed single-thread work is bound by the LCG loop itself, so all three are
  close. On 16 threads, steal-half spreads the heavy tasks.
* Fan-out / fan-in on 16 threads is the noisiest row (132–216 ns): 200k senders
  contend on one channel lock.
* tokio and Go tasks are `async` functions/goroutines; `rt` tasks are
  hand-written state machines (Zig 0.17 has no async). `rt` has no timers or
  I/O reactor yet.
* "before" fan-in: every blocked sender holds an OS thread on `Io.Threaded`.
