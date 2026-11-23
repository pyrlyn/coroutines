# Evented runtime vs std.Io.Threaded (2026-11-10)

Raw tables: `evented-linux-aarch64.md` (ReleaseFast), `evented-debug-linux-aarch64.md` and
`evented-debug-darwin-arm64.md` (Debug). Suite `SUITES=evented bench/run.sh`. Median of 5 fresh
processes per row. Zig 0.17.1. Linux = Ubuntu 26.04 in a Lima `vz` VM (4 vCPU, 4 GiB) on
an Apple M3 Max. macOS = the same Mac natively (16 CPUs).

Why macOS has only Debug numbers: on libdispatch every `ev-*` variant segfaults in a ReleaseFast
build. That is the upstream fiber bug in optimized builds; see `src/vendor/zig-0.17.1/README.md`
and `evented.allow_optimized`. The Linux ReleaseFast runs (5 per row) all completed. The same
build's test binary crashed in 3 of 15 runs (`spawnEach` test), so treat the optimized evented
path as experimental.

| variant | Linux ReleaseFast ns/op | Linux Debug ns/op | macOS Debug ns/op | Linux vol ctxsw (ReleaseFast) |
|---|---:|---:|---:|---:|
| io-switch (Threaded, per handoff) | 9,964.8 | 10,630.7 | 2,337.6 | 400,019 |
| ev-switch (evented, per handoff) | 592.4 | 12,593.8 | 1,011.3 | 10,015 |
| io-group (Threaded, per task) | 539.9 | 1,678.0 | 525.1 | 28 |
| ev-group (evented, per task) | 439.2 | 4,779.1 | 23,705.3 | 10,018 |
| io-dispatch (Threaded, per message) | 149.9 | 323.0 | 127.0 | 1,303 |
| ev-dispatch (evented, per message) | 138.6 | 631.8 | 870.1 | 10,551 |

Measured:
* Linux ReleaseFast: a channel handoff costs 592 ns on io_uring fibers vs 9,965 ns on
  `Threaded` (16.8× less). Voluntary context switches drop from 400,019 to 10,015 for 400,000
  handoffs. `spawnEach` and `Dispatcher` are 19% and 8% faster per item.
* Every evented fiber reserves a 60 MiB stack (upstream `min_stack_size`), so alloc bytes
  are large: 4.0 GB of address space for 65 fibers in `ev-group`. Peak RSS was 9.0 MB on
  Linux ReleaseFast, 99 MB on macOS Debug, and 964 MB in macOS Debug `ev-dispatch`.
* macOS Debug: `ev-switch` beats `io-switch` (1,011 vs 2,338 ns). `ev-group` is 45× slower per task than
  `io-group` (246k minor page faults), and `ev-dispatch` is 6.9× slower.

Not measured: optimized macOS, and evented on real Linux hardware (VM only).
