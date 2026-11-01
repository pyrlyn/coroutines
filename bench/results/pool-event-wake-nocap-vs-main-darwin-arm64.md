# Benchmark: pool-event-wake without cap_wake vs main (darwin-arm64)

No spin, but every run wakes all spawned threads.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 20.596 | +62% | 12.7 | 81.0 | +536% | 2.0 | 2.7 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 201.543 | +7% | 189.0 | 268.9 | +42% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 214.567 | -5% | 842.2 | 889.4 | +6% | 2.2 | 2.7 | RSS WORSE |
| sm-repeat t=10000 | 309.592 | 304.772 | -2% | 3770.9 | 3826.4 | +1% | 2.9 | 2.9 |  |
| sm-repeat t=100000 | 260.883 | 260.924 | +0% | 3623.8 | 3640.6 | +0% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 500.948 | +1% | 7039.6 | 7073.7 | +0% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 82.665 | +12% | 72.8 | 142.9 | +96% | 2.0 | 2.6 | time ~noise, CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 387.644 | +4% | 370.9 | 455.3 | +23% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 405.107 | -2% | 1479.9 | 1530.6 | +3% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 510.486 | +7% | 5814.1 | 5826.3 | +0% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 387.368 | -1% | 5662.5 | 5659.4 | -0% | 4.9 | 5.0 |  |
| sm-repeat-skew t=1000000 | 762.909 | 762.481 | -0% | 11286.2 | 11294.8 | +0% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 24.122 | +66% | 14.5 | 83.6 | +475% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 252.575 | +8% | 234.1 | 327.5 | +40% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 263.305 | -2% | 1023.8 | 1086.7 | +6% | 2.7 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 333.199 | -4% | 4501.9 | 4473.4 | -1% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.276 | -0% | 4519.0 | 4529.5 | +0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 633.670 | +0% | 9062.9 | 9046.7 | -0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.717 | +10% | 11.6 | 17.2 | +48% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 186.184 | +0% | 185.4 | 192.7 | +4% | 2.0 | 2.6 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 193.835 | -0% | 775.0 | 779.6 | +1% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.651 | +0% | 3185.5 | 3196.2 | +0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 707.656 | +0% | 10722.1 | 10720.6 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7403.963 | +2% | 106694.8 | 106757.6 | +0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 42.773 | +31% | 6.8 | 49.1 | +626% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 121.579 | +4% | 90.4 | 130.5 | +44% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 126.176 | -3% | 367.7 | 386.9 | +5% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 327.510 | -3% | 3765.7 | 3823.5 | +2% | 2.9 | 2.9 |  |
| sm-repeat-gap t=100000 | 270.189 | 266.960 | -1% | 3596.3 | 3626.4 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 490.066 | -4% | 7067.4 | 7093.6 | +0% | 25.5 | 25.5 |  |

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
