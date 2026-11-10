# Benchmark: evented (debug-linux-aarch64)

- Date: 2026-11-10T05:38Z
- Machine: Lima vz VM (4 vCPU, 4 GiB) on Ivan's Mac
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: -, 4 logical CPUs
- Zig: 0.17.1, Debug
- Available RAM at start: 3337 MB

## std.Io.Threaded vs evented runtime (coroutines.evented)

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| io-switch | 400000 | 4252262933 | 10630.7 | 1 | 106 | 2 | 1 | 0 | 5.4 | 0.0 | 5.4 | 745 | 8 | 400042 | 4 | 0 | 0 | 0 |
| ev-switch | 400000 | 5037500501 | 12593.8 | 1 | 63508480 | 2 | 1 | 0 | 68.2 | 0.0 | 68.2 | 16261 | 9 | 410012 | 3 | 0 | 0 | 0 |
| io-group | 10000 | 16779561 | 1678.0 | 16 | 1152 | 4 | 1 | 0 | 10.1 | 0.0 | 10.1 | 899 | 8 | 28 | 5 | 0 | 0 | 0 |
| ev-group | 10000 | 47791417 | 4779.1 | 7 | 378408960 | 4 | 1 | 0 | 372.9 | 0.0 | 372.9 | 93281 | 9 | 10035 | 0 | 0 | 0 | 0 |
| io-dispatch | 100000 | 32304656 | 323.0 | 4 | 224 | 4 | 1 | 0 | 12.5 | 0.0 | 12.5 | 957 | 7 | 1122 | 105 | 0 | 0 | 0 |
| ev-dispatch | 100000 | 63176844 | 631.8 | 5 | 252448768 | 4 | 1 | 0 | 253.0 | 0.0 | 253.0 | 62527 | 10 | 10518 | 3 | 0 | 0 | 0 |

