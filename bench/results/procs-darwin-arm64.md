# Benchmark: procs (darwin-arm64)

- Date: 2026-10-31T15:17Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 45507 MB

## Processes vs coroutines, same 10,000-task workload

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sequential | 10000 | 17324291 | 1732.4 | 0 | 0 | 1 | 1 | 0 | 1.9 | 0.0 | 1.9 | 212 | 0 | 0 | 24 | 0 | 0 | 0 |
| procs-2 | 10000 | 11698125 | 1169.8 | 0 | 0 | 1 | 3 | 337167 | 2.1 | 3.9 | 6.1 | 228 | 0 | 3 | 14 | 428 | 0 | 49 |
| sm-1thread | 10000 | 16652541 | 1665.3 | 1 | 240000 | 1 | 1 | 0 | 2.2 | 0.0 | 2.2 | 227 | 0 | 0 | 18 | 0 | 0 | 0 |
| sm-parallel | 10000 | 1548959 | 154.9 | 1 | 240000 | 16 | 1 | 0 | 2.5 | 0.0 | 2.5 | 260 | 0 | 0 | 64 | 0 | 0 | 0 |
| io-group | 10000 | 32599416 | 3259.9 | 10000 | 640000 | 16 | 1 | 0 | 2.8 | 0.0 | 2.8 | 10259 | 0 | 0 | 10230 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
