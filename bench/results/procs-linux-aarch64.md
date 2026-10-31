# Benchmark: procs (linux-aarch64)

- Date: 2026-10-31T15:13Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 8 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Processes vs coroutines, same 10,000-task workload

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sequential | 10000 | 16717502 | 1671.8 | 0 | 0 | 1 | 1 | 0 | 1.4 | 0.0 | 1.4 | 153 | 0 | 0 | 0 | 0 | 0 | 0 |
| procs2 | 10000 | 9057671 | 905.8 | 0 | 0 | 1 | 3 | 321710 | 1.7 | 1.5 | 4.7 | 170 | 0 | 6 | 0 | 305 | 2 | 1 |
| sm-1thread | 10000 | 15300578 | 1530.1 | 1 | 240000 | 1 | 1 | 0 | 1.7 | 0.0 | 1.7 | 211 | 0 | 0 | 0 | 0 | 0 | 0 |
| sm-parallel | 10000 | 2564722 | 256.5 | 1 | 240000 | 8 | 1 | 0 | 5.9 | 0.0 | 5.9 | 681 | 0 | 2 | 0 | 0 | 0 | 0 |
| io-group | 10000 | 82798467 | 8279.8 | 10000 | 640000 | 8 | 1 | 0 | 4.3 | 0.0 | 4.3 | 10622 | 0 | 11909 | 1 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Columns: allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); "RSS MB total" = self + (procs-1) x largest child.
