# Benchmark: pool-spin-config default (adaptive + cap_wake) vs main (darwin-arm64)

PoolOptions.spin = adaptive (start 4 us, max 50 us), cap_wake = true.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 12.425 | -2% | 12.7 | 13.1 | +3% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 189.209 | 183.905 | -3% | 189.0 | 184.4 | -2% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat t=1024 | 225.741 | 216.489 | -4% | 842.2 | 891.8 | +6% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat t=10000 | 309.592 | 303.815 | -2% | 3770.9 | 3818.3 | +1% | 2.9 | 2.9 |  |
| sm-repeat t=100000 | 260.883 | 264.311 | +1% | 3623.8 | 3649.5 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 509.729 | +2% | 7039.6 | 7098.0 | +1% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 73.686 | +0% | 72.8 | 73.0 | +0% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 371.044 | -0% | 370.9 | 371.2 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 405.621 | -2% | 1479.9 | 1514.2 | +2% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 514.770 | +8% | 5814.1 | 5760.6 | -1% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 393.370 | +1% | 5662.5 | 5639.2 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 752.224 | -1% | 11286.2 | 11519.0 | +2% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 14.916 | +3% | 14.5 | 15.6 | +7% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 233.899 | -0% | 234.1 | 234.5 | +0% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 263.307 | -2% | 1023.8 | 1082.6 | +6% | 2.7 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 333.839 | -4% | 4501.9 | 4483.5 | -0% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 307.650 | -0% | 4519.0 | 4543.0 | +1% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 632.173 | +0% | 9062.9 | 9090.1 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 11.788 | +2% | 11.6 | 12.3 | +6% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 190.500 | +3% | 185.4 | 191.3 | +3% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 193.848 | -0% | 775.0 | 778.0 | +0% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.366 | -0% | 3185.5 | 3190.3 | +0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 707.675 | +0% | 10722.1 | 10721.5 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7261.752 | -0% | 106694.8 | 106897.2 | +0% | 25.5 | 25.4 |  |
| sm-repeat-gap t=16 | 32.627 | 33.130 | +2% | 6.8 | 7.8 | +16% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 116.911 | +0% | 90.4 | 91.1 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 126.217 | -3% | 367.7 | 381.6 | +4% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 339.081 | +0% | 3765.7 | 3789.0 | +1% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 270.375 | +0% | 3596.3 | 3601.4 | +0% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 489.554 | -4% | 7067.4 | 7107.0 | +1% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: RSS WORSE
- sm-repeat t=256: RSS WORSE
- sm-repeat t=1024: RSS WORSE
- sm-repeat-skew t=16: RSS WORSE
- sm-repeat-skew t=256: RSS WORSE
- sm-repeat-skew t=1024: RSS WORSE
- sm-repeat-big t=16: RSS WORSE
- sm-repeat-big t=256: RSS WORSE
- sm-repeat-big t=1024: RSS WORSE
- sm-repeat-long t=16: RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: RSS WORSE
- sm-repeat-gap t=1024: RSS WORSE
