# Benchmark: hybrid (darwin-arm64)

- Date: 2026-10-31T15:25Z
- Machine: Ivan's Mac
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Available RAM at start: 42244 MB

## Four backends by task count N

Median of 3 runs, each a fresh process. processes = min(N, 16 CPUs) worker processes. hybrid = processes while N <= 256, Io coroutines above. RSS = parent + sum of children peak RSS. CPU % = (user + sys CPU time of the variant and its children, from getrusage) / wall time of the same interval (incl. setup such as thread pool and allocation); 100% = one core busy. wall ms = timed region only.

| variant | N | wall ms | RSS MB | CPU % | hybrid mode |
|---|---:|---:|---:|---:|---|
| state machine | 16 | 0.14 | 2.2 | 244 |  |
| Io | 16 | 0.18 | 2.7 | 335 |  |
| processes | 16 | 5.85 | 33.8 | 640 |  |
| hybrid | 16 | 5.56 | 33.1 | 643 | processes |
| state machine | 64 | 0.17 | 2.2 | 263 |  |
| Io | 64 | 0.34 | 2.4 | 304 |  |
| processes | 64 | 5.81 | 33.8 | 623 |  |
| hybrid | 64 | 5.43 | 33.1 | 645 | processes |
| state machine | 255 | 0.48 | 2.2 | 164 |  |
| Io | 255 | 1.08 | 2.8 | 363 |  |
| processes | 255 | 5.59 | 33.8 | 664 |  |
| hybrid | 255 | 5.50 | 33.1 | 624 | processes |
| state machine | 256 | 0.48 | 2.2 | 156 |  |
| Io | 256 | 1.05 | 2.7 | 351 |  |
| processes | 256 | 5.81 | 33.9 | 595 |  |
| hybrid | 256 | 5.54 | 33.1 | 616 | processes |
| state machine | 257 | 0.46 | 2.2 | 156 |  |
| Io | 257 | 1.12 | 2.6 | 327 |  |
| processes | 257 | 6.16 | 33.8 | 593 |  |
| hybrid | 257 | 0.96 | 2.7 | 342 | **Io (switched)** |
| state machine | 1024 | 0.50 | 2.3 | 405 |  |
| Io | 1024 | 3.67 | 2.7 | 328 |  |
| processes | 1024 | 6.04 | 33.8 | 618 |  |
| hybrid | 1024 | 3.98 | 2.7 | 319 | **Io (switched)** |
| state machine | 10000 | 1.85 | 2.5 | 1034 |  |
| Io | 10000 | 37.63 | 2.8 | 323 |  |
| processes | 10000 | 7.63 | 33.8 | 739 |  |
| hybrid | 10000 | 32.73 | 2.9 | 321 | **Io (switched)** |


Analysis: see [README](../../README.md#hybrid-backend). Linux not run for this suite (macOS only, by request).
