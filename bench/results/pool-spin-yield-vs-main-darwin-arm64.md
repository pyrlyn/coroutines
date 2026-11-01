# Benchmark: pool spin-then-yield vs main (darwin-arm64)

Spin 2 us, then up to 16 sched_yield calls, then futex sleep; wakes all threads.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 17.082 | +34% | 12.7 | 208.3 | +1536% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 202.022 | +7% | 189.0 | 631.7 | +234% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 214.581 | -5% | 842.2 | 1114.2 | +32% | 2.2 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 334.615 | +8% | 3770.9 | 3764.9 | -0% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 273.231 | +5% | 3623.8 | 3635.3 | +0% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 497.128 | -0% | 7039.6 | 7124.2 | +1% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 77.318 | +5% | 72.8 | 439.7 | +504% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 379.049 | +2% | 370.9 | 898.5 | +142% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 398.477 | -3% | 1479.9 | 2092.6 | +41% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 475.710 | -0% | 5814.1 | 5958.9 | +2% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 401.633 | +3% | 5662.5 | 5611.7 | -1% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 757.314 | -1% | 11286.2 | 11431.4 | +1% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 21.272 | +46% | 14.5 | 253.8 | +1647% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 251.244 | +7% | 234.1 | 656.9 | +181% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 267.904 | -0% | 1023.8 | 1329.1 | +30% | 2.7 | 3.1 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 331.400 | -5% | 4501.9 | 4491.3 | -0% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.592 | -0% | 4519.0 | 4555.2 | +1% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 632.133 | +0% | 9062.9 | 9086.5 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.677 | +9% | 11.6 | 37.6 | +224% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 185.797 | +0% | 185.4 | 215.3 | +16% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 192.762 | -1% | 775.0 | 796.6 | +3% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 227.900 | -1% | 3185.5 | 3176.7 | -0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 703.121 | -0% | 10722.1 | 10658.5 | -1% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7196.466 | -1% | 106694.8 | 106476.5 | -0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 49.064 | +50% | 6.8 | 159.9 | +2267% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 116.956 | +0% | 90.4 | 399.8 | +342% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 123.433 | -6% | 367.7 | 630.2 | +71% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 334.980 | -1% | 3765.7 | 3965.2 | +5% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 270.398 | +0% | 3596.3 | 3613.3 | +0% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 497.324 | -3% | 7067.4 | 7025.8 | -1% | 25.5 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat t=256: CPU WORSE, RSS WORSE
- sm-repeat t=1024: CPU WORSE, RSS WORSE
- sm-repeat-skew t=16: CPU WORSE, RSS WORSE
- sm-repeat-skew t=256: CPU WORSE, RSS WORSE
- sm-repeat-skew t=1024: CPU WORSE, RSS WORSE
- sm-repeat-big t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-big t=256: CPU WORSE, RSS WORSE
- sm-repeat-big t=1024: CPU WORSE, RSS WORSE
- sm-repeat-long t=16: CPU WORSE, RSS WORSE
- sm-repeat-long t=256: CPU WORSE, RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: CPU WORSE, RSS WORSE
- sm-repeat-gap t=1024: CPU WORSE, RSS WORSE
