# Benchmark: sweep (darwin-arm64)

- Date: 2026-10-31T15:17Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 45507 MB

## Process sweep: N worker processes vs coroutines, same 10,000 tasks

Median of 3 runs. N doubles from 1 while N <= 1024 and the projected total RSS of the next N stays under 50% of available RAM (22753 MB of 45507 MB). Children RSS = sum of each child's own peak RSS (wait4 rusage per child).

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| procs-1 | 10000 | 19604250 | 1960.4 | 0 | 0 | 1 | 2 | 204625 | 2.1 | 2.0 | 4.1 | 225 | 0 | 2 | 13 | 214 | 0 | 14 |
| procs-2 | 10000 | 11260042 | 1126.0 | 0 | 0 | 1 | 3 | 321000 | 2.1 | 3.9 | 6.1 | 229 | 0 | 3 | 13 | 427 | 0 | 34 |
| procs-4 | 10000 | 7198500 | 719.9 | 0 | 0 | 1 | 5 | 626916 | 2.1 | 7.9 | 10.0 | 233 | 0 | 4 | 14 | 856 | 0 | 72 |
| procs-8 | 10000 | 5922125 | 592.2 | 0 | 0 | 1 | 9 | 1048125 | 2.2 | 15.8 | 18.0 | 242 | 0 | 11 | 15 | 1715 | 0 | 144 |
| procs-16 | 10000 | 6423834 | 642.4 | 0 | 0 | 1 | 17 | 2466959 | 2.2 | 31.6 | 33.8 | 261 | 0 | 21 | 17 | 3428 | 0 | 343 |
| procs-32 | 10000 | 9566958 | 956.7 | 0 | 0 | 1 | 33 | 5353375 | 2.2 | 63.2 | 65.4 | 292 | 0 | 22 | 23 | 6861 | 0 | 825 |
| procs-64 | 10000 | 16081750 | 1608.2 | 0 | 0 | 1 | 65 | 11207750 | 2.2 | 126.3 | 128.5 | 357 | 0 | 11 | 36 | 13717 | 0 | 2110 |
| procs-128 | 10000 | 29992375 | 2999.2 | 0 | 0 | 1 | 129 | 27535875 | 2.2 | 252.6 | 254.9 | 487 | 0 | 11 | 97 | 27433 | 0 | 2528 |
| procs-256 | 10000 | 56214875 | 5621.5 | 0 | 0 | 1 | 257 | 53862875 | 2.3 | 504.8 | 507.0 | 747 | 0 | 11 | 201 | 54832 | 0 | 5084 |
| procs-512 | 10000 | 127735291 | 12773.5 | 0 | 0 | 1 | 513 | 124298583 | 2.3 | 1009.8 | 1012.1 | 1262 | 0 | 4 | 420 | 109683 | 0 | 17287 |
| procs-1024 | 10000 | 645919417 | 64591.9 | 0 | 0 | 1 | 1025 | 313389417 | 2.5 | 2020.0 | 2022.5 | 2374 | 0 | 18 | 1470 | 219404 | 0 | 326980 |
| sm-parallel | 10000 | 1548583 | 154.9 | 1 | 240000 | 16 | 1 | 0 | 2.5 | 0.0 | 2.5 | 260 | 0 | 0 | 48 | 0 | 0 | 0 |
| io-group | 10000 | 30229708 | 3023.0 | 10000 | 640000 | 16 | 1 | 0 | 2.8 | 0.0 | 2.8 | 10260 | 0 | 0 | 10204 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
