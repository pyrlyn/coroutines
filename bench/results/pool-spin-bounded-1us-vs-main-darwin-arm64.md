# Benchmark: pool-spin-bounded 1us vs main (darwin-arm64)

Pool idle threads spin for at most 1 us, then futex sleep; all spawned threads woken per run.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 22.131 | +74% | 12.7 | 88.8 | +598% | 2.0 | 2.7 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 205.632 | +9% | 189.0 | 282.2 | +49% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 216.806 | -4% | 842.2 | 899.3 | +7% | 2.2 | 2.7 | RSS WORSE |
| sm-repeat t=10000 | 309.592 | 309.947 | +0% | 3770.9 | 3781.8 | +0% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 264.863 | +2% | 3623.8 | 3661.1 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 493.546 | -1% | 7039.6 | 7146.4 | +2% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 109.438 | +49% | 72.8 | 152.2 | +109% | 2.0 | 2.6 | time ~noise, CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 389.237 | +5% | 370.9 | 465.5 | +26% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 403.711 | -2% | 1479.9 | 1538.1 | +4% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 490.527 | +3% | 5814.1 | 5822.9 | +0% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 388.745 | -0% | 5662.5 | 5656.2 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 759.818 | -0% | 11286.2 | 11328.0 | +0% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 26.158 | +80% | 14.5 | 93.9 | +546% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 252.243 | +8% | 234.1 | 336.4 | +44% | 2.1 | 2.8 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 262.288 | -3% | 1023.8 | 1090.5 | +7% | 2.7 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 333.281 | -4% | 4501.9 | 4469.2 | -1% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 308.653 | -0% | 4519.0 | 4538.1 | +0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 633.773 | +0% | 9062.9 | 9073.0 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.762 | +10% | 11.6 | 18.7 | +61% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 186.704 | +1% | 185.4 | 195.3 | +5% | 2.0 | 2.6 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 194.160 | -0% | 775.0 | 781.4 | +1% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 231.189 | +1% | 3185.5 | 3181.8 | -0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 706.403 | +0% | 10722.1 | 10721.2 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7336.550 | +1% | 106694.8 | 106764.7 | +0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 42.319 | +30% | 6.8 | 51.9 | +669% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 121.108 | +4% | 90.4 | 135.0 | +49% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 126.409 | -3% | 367.7 | 390.9 | +6% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 330.378 | -2% | 3765.7 | 3820.4 | +1% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 273.793 | +1% | 3596.3 | 3613.0 | +0% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 490.820 | -4% | 7067.4 | 7126.1 | +1% | 25.5 | 25.5 |  |

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
