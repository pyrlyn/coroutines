# Benchmark: pool-spin-bounded 50us vs main (darwin-arm64)

Pool idle threads spin for at most 50 us, then futex sleep; all spawned threads woken per run.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 23.321 | +83% | 12.7 | 305.2 | +2297% | 2.0 | 2.7 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 200.450 | +6% | 189.0 | 636.2 | +237% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 212.605 | -6% | 842.2 | 1198.8 | +42% | 2.2 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 311.645 | +1% | 3770.9 | 3917.6 | +4% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 262.984 | +1% | 3623.8 | 3669.4 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 489.383 | -2% | 7039.6 | 7164.1 | +2% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 91.480 | +24% | 72.8 | 517.7 | +611% | 2.0 | 2.6 | time ~noise, CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 369.519 | -0% | 370.9 | 817.4 | +120% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 398.035 | -4% | 1479.9 | 1897.0 | +28% | 2.3 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 506.673 | +6% | 5814.1 | 5954.4 | +2% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 394.710 | +1% | 5662.5 | 5671.4 | +0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 764.700 | +0% | 11286.2 | 11400.5 | +1% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 19.864 | +37% | 14.5 | 287.3 | +1877% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 252.808 | +8% | 234.1 | 690.4 | +195% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 257.372 | -4% | 1023.8 | 1380.0 | +35% | 2.7 | 3.1 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 331.568 | -5% | 4501.9 | 4634.3 | +3% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.443 | -0% | 4519.0 | 4549.3 | +1% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 629.057 | -0% | 9062.9 | 9096.2 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.557 | +8% | 11.6 | 40.8 | +252% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 187.768 | +1% | 185.4 | 224.1 | +21% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 195.825 | +1% | 775.0 | 806.8 | +4% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.097 | -0% | 3185.5 | 3202.0 | +1% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 705.501 | +0% | 10722.1 | 10732.0 | +0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7492.737 | +3% | 106694.8 | 106631.9 | -0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 50.013 | +53% | 6.8 | 194.8 | +2783% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 117.357 | +1% | 90.4 | 286.7 | +217% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 122.201 | -6% | 367.7 | 548.2 | +49% | 2.3 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 340.708 | +1% | 3765.7 | 4013.7 | +7% | 2.9 | 2.9 |  |
| sm-repeat-gap t=100000 | 270.189 | 266.021 | -2% | 3596.3 | 3659.3 | +2% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 490.880 | -4% | 7067.4 | 7136.1 | +1% | 25.5 | 25.5 |  |

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
