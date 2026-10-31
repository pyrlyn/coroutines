# Benchmark: spawn (darwin-arm64)

- Date: 2026-10-31T15:13Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast

## Spawn and run 10,000 small tasks

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-1thread | 10000 | 15200917 | 1520.1 | 1 | 240000 | 1 | 1 | 0 | 2.1 | 0.0 | 2.1 | 225 | 0 | 0 | 13 | 0 | 0 | 0 |
| sm-parallel | 10000 | 1466292 | 146.6 | 1 | 240000 | 16 | 1 | 0 | 2.4 | 0.0 | 2.4 | 257 | 0 | 0 | 54 | 0 | 0 | 0 |
| io-group | 10000 | 30398958 | 3039.9 | 10000 | 640000 | 16 | 1 | 0 | 2.8 | 0.0 | 2.8 | 10260 | 0 | 0 | 10216 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Columns: allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); "RSS MB total" = self + (procs-1) x largest child.
