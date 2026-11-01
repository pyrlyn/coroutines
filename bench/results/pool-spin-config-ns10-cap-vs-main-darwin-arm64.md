# Benchmark: pool-spin-config spin=.ns 10us + cap_wake vs main (darwin-arm64)

PoolOptions.spin = .{ .ns = 10_000 }, cap_wake = true.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 12.369 | -3% | 12.7 | 13.1 | +3% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 189.209 | 184.469 | -3% | 189.0 | 185.0 | -2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=1024 | 225.741 | 213.847 | -5% | 842.2 | 939.2 | +12% | 2.2 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 305.676 | -1% | 3770.9 | 3859.5 | +2% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 261.754 | +0% | 3623.8 | 3652.5 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 505.795 | +2% | 7039.6 | 7070.6 | +0% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 72.502 | -1% | 72.8 | 72.4 | -1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 372.337 | +0% | 370.9 | 372.7 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 400.936 | -3% | 1479.9 | 1577.8 | +7% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 496.222 | +4% | 5814.1 | 5755.6 | -1% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 387.004 | -1% | 5662.5 | 5638.1 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 754.880 | -1% | 11286.2 | 11368.7 | +1% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 14.735 | +1% | 14.5 | 15.4 | +6% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 233.452 | -0% | 234.1 | 234.3 | +0% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 259.751 | -3% | 1023.8 | 1131.1 | +10% | 2.7 | 3.1 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 331.505 | -5% | 4501.9 | 4503.8 | +0% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 307.916 | -0% | 4519.0 | 4544.2 | +1% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 631.678 | +0% | 9062.9 | 9077.5 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 11.806 | +2% | 11.6 | 12.5 | +8% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 183.782 | -1% | 185.4 | 184.8 | -0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 192.987 | -1% | 775.0 | 780.6 | +1% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 228.019 | -1% | 3185.5 | 3174.8 | -0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 701.613 | -1% | 10722.1 | 10674.8 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7259.893 | -0% | 106694.8 | 106019.0 | -1% | 25.5 | 25.4 |  |
| sm-repeat-gap t=16 | 32.627 | 33.179 | +2% | 6.8 | 7.8 | +16% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 116.669 | +0% | 90.4 | 91.2 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 124.277 | -5% | 367.7 | 410.8 | +12% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 330.741 | -2% | 3765.7 | 3849.0 | +2% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 264.769 | -2% | 3596.3 | 3641.4 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 490.884 | -4% | 7067.4 | 7133.1 | +1% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: RSS WORSE
- sm-repeat t=256: RSS WORSE
- sm-repeat t=1024: CPU WORSE, RSS WORSE
- sm-repeat-skew t=16: RSS WORSE
- sm-repeat-skew t=256: RSS WORSE
- sm-repeat-skew t=1024: RSS WORSE
- sm-repeat-big t=16: RSS WORSE
- sm-repeat-big t=256: RSS WORSE
- sm-repeat-big t=1024: CPU WORSE, RSS WORSE
- sm-repeat-long t=16: RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: RSS WORSE
- sm-repeat-gap t=1024: CPU WORSE, RSS WORSE
