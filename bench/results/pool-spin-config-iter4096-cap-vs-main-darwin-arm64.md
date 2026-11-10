# Benchmark: pool-spin-config spin=.iterations 4096 + cap_wake vs main (darwin-arm64)

PR #13 spin (4096 polls) plus cap_wake.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 12.388 | -3% | 12.7 | 13.5 | +6% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 189.209 | 185.887 | -2% | 189.0 | 187.3 | -1% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat t=1024 | 225.741 | 213.203 | -6% | 842.2 | 1147.2 | +36% | 2.2 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 307.675 | -1% | 3770.9 | 3930.2 | +4% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 269.954 | +3% | 3623.8 | 3627.3 | +0% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 495.814 | -0% | 7039.6 | 7095.4 | +1% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 74.986 | +2% | 72.8 | 73.2 | +1% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 370.724 | -0% | 370.9 | 371.5 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 397.285 | -4% | 1479.9 | 1793.6 | +21% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 505.250 | +6% | 5814.1 | 5919.8 | +2% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 387.519 | -1% | 5662.5 | 5661.8 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 759.641 | -0% | 11286.2 | 11313.1 | +0% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 14.819 | +2% | 14.5 | 16.4 | +13% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 238.551 | +2% | 234.1 | 240.0 | +3% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 261.825 | -3% | 1023.8 | 1344.5 | +31% | 2.7 | 3.0 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 333.228 | -4% | 4501.9 | 4603.6 | +2% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.977 | -0% | 4519.0 | 4545.2 | +1% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 632.660 | +0% | 9062.9 | 9091.6 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 11.956 | +3% | 11.6 | 13.3 | +15% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 185.568 | +0% | 185.4 | 187.2 | +1% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 193.946 | -0% | 775.0 | 808.7 | +4% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.830 | +0% | 3185.5 | 3196.5 | +0% | 2.8 | 2.8 |  |
| sm-repeat-long t=100000 | 705.200 | 704.673 | -0% | 10722.1 | 10727.4 | +0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7250.344 | -0% | 106694.8 | 106764.0 | +0% | 25.5 | 25.4 |  |
| sm-repeat-gap t=16 | 32.627 | 33.075 | +1% | 6.8 | 8.1 | +20% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 116.508 | +0% | 90.4 | 91.6 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 122.310 | -6% | 367.7 | 488.9 | +33% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 328.812 | -3% | 3765.7 | 3956.7 | +5% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 266.621 | -1% | 3596.3 | 3655.3 | +2% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 486.564 | -5% | 7067.4 | 7131.2 | +1% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: RSS WORSE
- sm-repeat t=256: RSS WORSE
- sm-repeat t=1024: CPU WORSE, RSS WORSE
- sm-repeat-skew t=16: RSS WORSE
- sm-repeat-skew t=256: RSS WORSE
- sm-repeat-skew t=1024: CPU WORSE, RSS WORSE
- sm-repeat-big t=16: CPU WORSE, RSS WORSE
- sm-repeat-big t=256: RSS WORSE
- sm-repeat-big t=1024: CPU WORSE, RSS WORSE
- sm-repeat-long t=16: CPU WORSE, RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: RSS WORSE
- sm-repeat-gap t=1024: CPU WORSE, RSS WORSE
