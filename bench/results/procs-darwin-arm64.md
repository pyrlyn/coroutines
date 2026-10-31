# Benchmark: procs (darwin-arm64)

- Date: 2026-10-31T15:13Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Processes vs coroutines, same 10,000-task workload

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sequential | 10000 | 16373667 | 1637.4 | 0 | 0 | 1 | 1 | 0 | 1.9 | 0.0 | 1.9 | 210 | 0 | 0 | 13 | 0 | 0 | 0 |
| procs2 | 10000 | 10878375 | 1087.8 | 0 | 0 | 1 | 3 | 264000 | 2.1 | 2.0 | 6.0 | 226 | 0 | 3 | 13 | 428 | 0 | 36 |
| sm-1thread | 10000 | 15078042 | 1507.8 | 1 | 240000 | 1 | 1 | 0 | 2.2 | 0.0 | 2.2 | 226 | 0 | 0 | 13 | 0 | 0 | 0 |
| sm-parallel | 10000 | 1454250 | 145.4 | 1 | 240000 | 16 | 1 | 0 | 2.5 | 0.0 | 2.5 | 258 | 0 | 0 | 42 | 0 | 0 | 0 |
| io-group | 10000 | 30038500 | 3003.9 | 10000 | 640000 | 16 | 1 | 0 | 2.7 | 0.0 | 2.7 | 10260 | 0 | 0 | 10230 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Columns: allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); "RSS MB total" = self + (procs-1) x largest child.
