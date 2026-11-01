# Benchmark: pool-adaptive-spin vs main (darwin-arm64)

Adaptive per-thread spin budget (start 4 us, x2 on hit up to 50 us, /2 on miss), wakes all threads.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 16.339 | +28% | 12.7 | 84.3 | +562% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 202.614 | +7% | 189.0 | 297.7 | +57% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 213.579 | -5% | 842.2 | 917.5 | +9% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat t=10000 | 309.592 | 309.861 | +0% | 3770.9 | 3833.6 | +2% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 267.590 | +3% | 3623.8 | 3612.2 | -0% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 494.953 | -1% | 7039.6 | 7148.5 | +2% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 80.715 | +10% | 72.8 | 166.4 | +129% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 380.192 | +2% | 370.9 | 478.0 | +29% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 402.864 | -2% | 1479.9 | 1552.3 | +5% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 517.582 | +8% | 5814.1 | 5801.6 | -0% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 394.607 | +1% | 5662.5 | 5641.8 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 756.866 | -1% | 11286.2 | 11434.8 | +1% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 19.817 | +36% | 14.5 | 91.5 | +530% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 247.912 | +6% | 234.1 | 341.5 | +46% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 260.067 | -3% | 1023.8 | 1108.7 | +8% | 2.7 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 333.695 | -4% | 4501.9 | 4485.4 | -0% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.095 | -0% | 4519.0 | 4539.1 | +0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 632.843 | +0% | 9062.9 | 9070.0 | +0% | 483.2 | 483.2 |  |
| sm-repeat-long t=16 | 11.604 | 12.614 | +9% | 11.6 | 19.8 | +71% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 185.132 | -0% | 185.4 | 194.8 | +5% | 2.0 | 2.6 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 192.713 | -1% | 775.0 | 776.1 | +0% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 228.472 | -1% | 3185.5 | 3172.0 | -0% | 2.8 | 2.8 |  |
| sm-repeat-long t=100000 | 705.200 | 700.800 | -1% | 10722.1 | 10671.3 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7468.676 | +3% | 106694.8 | 106057.7 | -1% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 40.553 | +24% | 6.8 | 47.8 | +607% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 120.713 | +4% | 90.4 | 141.5 | +57% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 125.379 | -4% | 367.7 | 397.7 | +8% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 336.130 | -0% | 3765.7 | 3803.2 | +1% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 268.120 | -1% | 3596.3 | 3640.0 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 496.267 | -3% | 7067.4 | 7089.5 | +0% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat t=256: CPU WORSE, RSS WORSE
- sm-repeat t=1024: RSS WORSE
- sm-repeat-skew t=16: CPU WORSE, RSS WORSE
- sm-repeat-skew t=256: CPU WORSE, RSS WORSE
- sm-repeat-skew t=1024: RSS WORSE
- sm-repeat-big t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-big t=256: CPU WORSE, RSS WORSE
- sm-repeat-big t=1024: RSS WORSE
- sm-repeat-long t=16: CPU WORSE, RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: CPU WORSE, RSS WORSE
- sm-repeat-gap t=1024: RSS WORSE
