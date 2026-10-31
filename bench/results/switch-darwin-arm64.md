# Benchmark: switch (darwin-arm64)

- Date: 2026-10-31T15:17Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 45507 MB

## Switch cost

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sm-switch | 10000000 | 13964458 | 1.4 | 0 | 0 | 1 | 1 | 0 | 1.9 | 0.0 | 1.9 | 211 | 0 | 0 | 14 | 0 | 0 | 0 |
| io-switch | 400000 | 753448041 | 1883.6 | 1 | 106 | 2 | 1 | 0 | 2.0 | 0.0 | 2.0 | 219 | 0 | 0 | 400628 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
