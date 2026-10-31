# Benchmark: spawn (linux-aarch64)

- Date: 2026-10-31T15:13Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 8 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Spawn and run 10,000 small tasks

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-1thread | 10000 | 15428954 | 1542.9 | 1 | 240000 | 1 | 1 | 0 | 1.6 | 0.0 | 1.6 | 212 | 0 | 0 | 0 | 0 | 0 | 0 |
| sm-parallel | 10000 | 2631388 | 263.1 | 1 | 240000 | 8 | 1 | 0 | 11.9 | 0.0 | 11.9 | 685 | 0 | 2 | 3 | 0 | 0 | 0 |
| io-group | 10000 | 76686977 | 7668.7 | 10000 | 640000 | 8 | 1 | 0 | 4.3 | 0.0 | 4.3 | 10621 | 0 | 11917 | 0 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Columns: allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); "RSS MB total" = self + (procs-1) x largest child.
