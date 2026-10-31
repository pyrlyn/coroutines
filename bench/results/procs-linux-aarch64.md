# Benchmark: procs (linux-aarch64)

- Date: 2026-10-31T15:18Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 4 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Processes vs coroutines, same 10,000-task workload

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sequential | 10000 | 17094543 | 1709.5 | 0 | 0 | 1 | 1 | 0 | 1.4 | 0.0 | 1.4 | 151 | 0 | 0 | 2 | 0 | 0 | 0 |
| procs-2 | 10000 | 9335796 | 933.6 | 0 | 0 | 1 | 3 | 332543 | 1.7 | 3.1 | 4.7 | 169 | 0 | 6 | 0 | 302 | 2 | 1 |
| sm-1thread | 10000 | 15477702 | 1547.8 | 1 | 240000 | 1 | 1 | 0 | 1.7 | 0.0 | 1.7 | 210 | 0 | 0 | 0 | 0 | 0 | 0 |
| sm-parallel | 10000 | 4198480 | 419.8 | 1 | 240000 | 4 | 1 | 0 | 4.8 | 0.0 | 4.8 | 417 | 0 | 2 | 4 | 0 | 0 | 0 |
| io-group | 10000 | 70187140 | 7018.7 | 10000 | 640000 | 4 | 1 | 0 | 2.9 | 0.0 | 2.9 | 10355 | 0 | 8602 | 1 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
