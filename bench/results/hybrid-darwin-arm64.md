# Benchmark: bytasks (darwin-arm64)

- Date: 2026-10-31T15:25Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 42244 MB

## Three backends by task count N

Median of 3 runs, each a fresh process. processes = min(N, 16 CPUs) worker processes. RSS = parent + sum of children peak RSS. CPU % = (user + sys CPU time of the variant and its children, from getrusage) / wall time of the same interval (incl. setup such as thread pool and allocation); 100% = one core busy. wall ms = timed region only.

| variant | N | wall ms | RSS MB | CPU % |
|---|---:|---:|---:|---:|
| state machine | 16 | 0.14 | 2.2 | 244 |
| Io | 16 | 0.18 | 2.7 | 335 |
| processes | 16 | 5.85 | 33.8 | 640 |
| state machine | 64 | 0.17 | 2.2 | 263 |
| Io | 64 | 0.34 | 2.4 | 304 |
| processes | 64 | 5.81 | 33.8 | 623 |
| state machine | 255 | 0.48 | 2.2 | 164 |
| Io | 255 | 1.08 | 2.8 | 363 |
| processes | 255 | 5.59 | 33.8 | 664 |
| state machine | 256 | 0.48 | 2.2 | 156 |
| Io | 256 | 1.05 | 2.7 | 351 |
| processes | 256 | 5.81 | 33.9 | 595 |
| state machine | 257 | 0.46 | 2.2 | 156 |
| Io | 257 | 1.12 | 2.6 | 327 |
| processes | 257 | 6.16 | 33.8 | 593 |
| state machine | 1024 | 0.50 | 2.3 | 405 |
| Io | 1024 | 3.67 | 2.7 | 328 |
| processes | 1024 | 6.04 | 33.8 | 618 |
| state machine | 10000 | 1.85 | 2.5 | 1034 |
| Io | 10000 | 37.63 | 2.8 | 323 |
| processes | 10000 | 7.63 | 33.8 | 739 |


Analysis: see [README](../../README.md#backends-by-task-count). Linux not run for this suite (macOS only, by request).
