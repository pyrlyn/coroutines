# Benchmark: spawn (linux-aarch64)

- Date: 2026-10-31T15:18Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 4 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Spawn and run 10,000 small tasks

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-1thread | 10000 | 15548661 | 1554.9 | 1 | 240000 | 1 | 1 | 0 | 1.7 | 0.0 | 1.7 | 210 | 0 | 0 | 0 | 0 | 0 | 0 |
| sm-parallel | 10000 | 4181354 | 418.1 | 1 | 240000 | 4 | 1 | 0 | 4.8 | 0.0 | 4.8 | 416 | 0 | 2 | 1 | 0 | 0 | 0 |
| io-group | 10000 | 70212765 | 7021.3 | 10000 | 640000 | 4 | 1 | 0 | 2.9 | 0.0 | 2.9 | 10357 | 0 | 8556 | 2 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
