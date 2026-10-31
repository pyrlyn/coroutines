# Benchmark: spawn (darwin-arm64)

- Date: 2026-10-31T15:17Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 45507 MB

## Spawn and run 10,000 small tasks

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-1thread | 10000 | 15287250 | 1528.7 | 1 | 240000 | 1 | 1 | 0 | 2.2 | 0.0 | 2.2 | 227 | 0 | 0 | 18 | 0 | 0 | 0 |
| sm-parallel | 10000 | 1507875 | 150.8 | 1 | 240000 | 16 | 1 | 0 | 2.5 | 0.0 | 2.5 | 260 | 0 | 0 | 63 | 0 | 0 | 0 |
| io-group | 10000 | 32102709 | 3210.3 | 10000 | 640000 | 16 | 1 | 0 | 2.7 | 0.0 | 2.7 | 10260 | 0 | 0 | 10205 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
