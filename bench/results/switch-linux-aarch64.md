# Benchmark: switch (linux-aarch64)

- Date: 2026-10-31T15:17Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 4 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Switch cost

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-switch | 10000000 | 16247038 | 1.6 | 0 | 0 | 1 | 1 | 0 | 1.4 | 0.0 | 1.4 | 150 | 0 | 0 | 2 | 0 | 0 | 0 |
| io-switch | 400000 | 4100660884 | 10251.7 | 1 | 106 | 2 | 1 | 0 | 1.9 | 0.0 | 1.9 | 223 | 0 | 400218 | 3 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
