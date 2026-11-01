# Benchmark: pool-spin-bounded 10us vs main (darwin-arm64)

Pool idle threads spin for at most 10 us (branch default), then futex sleep; all spawned threads woken per run.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 15.947 | +25% | 12.7 | 128.9 | +912% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 204.170 | +8% | 189.0 | 340.0 | +80% | 2.0 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 216.815 | -4% | 842.2 | 956.6 | +14% | 2.2 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 307.077 | -1% | 3770.9 | 3850.8 | +2% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 263.866 | +1% | 3623.8 | 3661.6 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 485.879 | -2% | 7039.6 | 7157.5 | +2% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 76.898 | +5% | 72.8 | 211.5 | +191% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 376.039 | +1% | 370.9 | 513.7 | +39% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 403.911 | -2% | 1479.9 | 1605.5 | +8% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 513.596 | +8% | 5814.1 | 5903.8 | +2% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 390.622 | +0% | 5662.5 | 5655.5 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 759.522 | -0% | 11286.2 | 11385.4 | +1% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 21.093 | +45% | 14.5 | 145.6 | +902% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 248.395 | +6% | 234.1 | 389.3 | +66% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 262.582 | -2% | 1023.8 | 1152.6 | +13% | 2.7 | 3.1 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 330.917 | -5% | 4501.9 | 4499.4 | -0% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 310.019 | +0% | 4519.0 | 4537.6 | +0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 629.626 | -0% | 9062.9 | 9089.5 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.555 | +8% | 11.6 | 22.5 | +94% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 186.850 | +1% | 185.4 | 203.7 | +10% | 2.0 | 2.6 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 194.939 | +0% | 775.0 | 788.2 | +2% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.636 | -0% | 3185.5 | 3183.0 | -0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 709.002 | +1% | 10722.1 | 10710.7 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7203.920 | -1% | 106694.8 | 106781.9 | +0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 41.011 | +26% | 6.8 | 77.7 | +1051% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 121.111 | +4% | 90.4 | 161.9 | +79% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 124.536 | -5% | 367.7 | 419.0 | +14% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 323.112 | -4% | 3765.7 | 3863.1 | +3% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 262.712 | -3% | 3596.3 | 3641.9 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 502.185 | -2% | 7067.4 | 7074.0 | +0% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat t=256: CPU WORSE, RSS WORSE
- sm-repeat t=1024: CPU WORSE, RSS WORSE
- sm-repeat-skew t=16: CPU WORSE, RSS WORSE
- sm-repeat-skew t=256: CPU WORSE, RSS WORSE
- sm-repeat-skew t=1024: RSS WORSE
- sm-repeat-big t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-big t=256: CPU WORSE, RSS WORSE
- sm-repeat-big t=1024: CPU WORSE, RSS WORSE
- sm-repeat-long t=16: CPU WORSE, RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: CPU WORSE, RSS WORSE
- sm-repeat-gap t=1024: CPU WORSE, RSS WORSE
