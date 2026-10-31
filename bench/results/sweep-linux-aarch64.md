# Benchmark: sweep (linux-aarch64)

- Date: 2026-10-31T15:18Z
- Machine: Lima VM (vz) on Ivan's Mac, host CPU Apple M3 Max
- OS: Ubuntu 26.04 LTS (Linux 7.0.0-38-generic)
- CPU: Apple M3 Max (virtualized), 4 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 3346 MB

## Process sweep: N worker processes vs coroutines, same 10,000 tasks

Median of 3 runs. N doubles from 1 while N <= 1024 and the projected total RSS of the next N stays under 50% of available RAM (1673 MB of 3346 MB). Children RSS = sum of each child's own peak RSS (wait4 rusage per child).

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| procs-1 | 10000 | 17395973 | 1739.6 | 0 | 0 | 1 | 2 | 174126 | 1.5 | 1.5 | 3.1 | 164 | 0 | 3 | 0 | 154 | 1 | 2 |
| procs-2 | 10000 | 8993842 | 899.4 | 0 | 0 | 1 | 3 | 292168 | 1.7 | 3.1 | 4.7 | 171 | 0 | 6 | 0 | 302 | 2 | 0 |
| procs-4 | 10000 | 5128071 | 512.8 | 0 | 0 | 1 | 5 | 577212 | 1.7 | 6.2 | 7.9 | 184 | 0 | 12 | 0 | 606 | 4 | 4 |
| procs-8 | 10000 | 7376041 | 737.6 | 0 | 0 | 1 | 9 | 5969950 | 1.7 | 12.0 | 13.6 | 210 | 0 | 10 | 0 | 1209 | 8 | 9 |
| procs-16 | 10000 | 8643674 | 864.4 | 0 | 0 | 1 | 17 | 7382292 | 1.7 | 24.6 | 26.3 | 288 | 0 | 22 | 0 | 2425 | 16 | 13 |
| procs-32 | 10000 | 11692773 | 1169.3 | 0 | 0 | 1 | 33 | 10948186 | 1.7 | 49.4 | 51.1 | 481 | 0 | 38 | 0 | 4912 | 32 | 28 |
| procs-64 | 10000 | 13038990 | 1303.9 | 0 | 0 | 1 | 65 | 12425778 | 1.7 | 98.8 | 100.5 | 813 | 0 | 66 | 0 | 9827 | 64 | 62 |
| procs-128 | 10000 | 19639151 | 1963.9 | 0 | 0 | 1 | 129 | 19178398 | 1.7 | 197.4 | 199.0 | 1160 | 0 | 128 | 1 | 19385 | 128 | 62 |
| procs-256 | 10000 | 40278059 | 4027.8 | 0 | 0 | 1 | 257 | 39491888 | 1.7 | 396.8 | 398.4 | 2220 | 0 | 256 | 5 | 38765 | 256 | 39 |
| procs-512 | 10000 | 81520706 | 8152.1 | 0 | 0 | 1 | 513 | 80082698 | 1.7 | 796.5 | 798.1 | 5285 | 0 | 511 | 3 | 78594 | 512 | 64 |
| procs-1024 | 10000 | 182685522 | 18268.6 | 0 | 0 | 1 | 1025 | 180030924 | 1.8 | 1580.5 | 1582.3 | 9469 | 0 | 1023 | 5 | 156156 | 1024 | 128 |

Stopped: next N would exceed the memory cap.
| sm-parallel | 10000 | 4373566 | 437.4 | 1 | 240000 | 4 | 1 | 0 | 4.8 | 0.0 | 4.8 | 417 | 0 | 2 | 6 | 0 | 0 | 0 |
| io-group | 10000 | 71312357 | 7131.2 | 10000 | 640000 | 4 | 1 | 0 | 2.9 | 0.0 | 2.9 | 10357 | 0 | 8446 | 0 | 0 | 0 | 0 |


Analysis of these numbers: see [README](../../README.md#analysis). Allocs/bytes via a counting allocator; RSS, page faults and context switches via getrusage (RUSAGE_SELF / RUSAGE_CHILDREN); per-child peak RSS via wait4 rusage, summed in "peak RSS MB (children, sum)".
