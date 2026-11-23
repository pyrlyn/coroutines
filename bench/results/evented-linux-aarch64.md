# Benchmark: evented (linux-aarch64)

- Date: 2026-11-10T05:37Z
- Machine: Lima vz VM (4 vCPU, 4 GiB) on Ivan's Mac
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: -, 4 logical CPUs
- Zig: 0.17.1, ReleaseFast
- Available RAM at start: 3333 MB

## std.Io.Threaded vs evented runtime (coroutines.evented)

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| io-switch | 400000 | 3985903013 | 9964.8 | 1 | 106 | 2 | 1 | 0 | 2.1 | 0.0 | 2.1 | 227 | 2 | 400019 | 0 | 0 | 0 | 0 |
| ev-switch | 400000 | 236969327 | 592.4 | 1 | 63508480 | 2 | 1 | 0 | 4.3 | 0.0 | 4.3 | 241 | 2 | 10015 | 1 | 0 | 0 | 0 |
| io-group | 10000 | 5398861 | 539.9 | 16 | 1152 | 4 | 1 | 0 | 2.7 | 0.0 | 2.7 | 376 | 2 | 28 | 0 | 0 | 0 | 0 |
| ev-group | 10000 | 4392272 | 439.2 | 17 | 1008209920 | 4 | 1 | 0 | 9.0 | 0.0 | 9.0 | 411 | 2 | 10018 | 2 | 0 | 0 | 0 |
| io-dispatch | 100000 | 14993701 | 149.9 | 4 | 224 | 4 | 1 | 0 | 7.1 | 0.0 | 7.1 | 435 | 2 | 1303 | 78 | 0 | 0 | 0 |
| ev-dispatch | 100000 | 13863653 | 138.6 | 5 | 252448768 | 4 | 1 | 0 | 8.9 | 0.0 | 8.9 | 391 | 2 | 10551 | 3 | 0 | 0 | 0 |

