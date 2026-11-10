# Benchmark: PR #13 as is (4096-poll spin, wakes all) vs main (darwin-arm64)

Reference: PR #13 unchanged, rebased on current main.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 19.683 | +55% | 12.7 | 252.4 | +1882% | 2.0 | 2.7 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 189.209 | 199.039 | +5% | 189.0 | 574.7 | +204% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 225.741 | 211.512 | -6% | 842.2 | 1150.8 | +37% | 2.2 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat t=10000 | 309.592 | 304.146 | -2% | 3770.9 | 3909.3 | +4% | 2.9 | 2.9 |  |
| sm-repeat t=100000 | 260.883 | 261.795 | +0% | 3623.8 | 3672.6 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 508.795 | +2% | 7039.6 | 7034.0 | -0% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 96.029 | +31% | 72.8 | 433.2 | +495% | 2.0 | 2.6 | time ~noise, CPU WORSE, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 372.272 | +0% | 370.9 | 726.7 | +96% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 397.011 | -4% | 1479.9 | 1792.9 | +21% | 2.3 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 516.709 | +8% | 5814.1 | 5936.6 | +2% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 392.897 | +1% | 5662.5 | 5645.3 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 760.286 | -0% | 11286.2 | 11262.7 | -0% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 22.504 | +55% | 14.5 | 278.5 | +1817% | 2.0 | 2.7 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 249.967 | +7% | 234.1 | 632.3 | +170% | 2.1 | 2.7 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 259.298 | -4% | 1023.8 | 1348.7 | +32% | 2.7 | 3.1 | CPU WORSE, RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 330.583 | -5% | 4501.9 | 4574.3 | +2% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 307.262 | -1% | 4519.0 | 4538.9 | +0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 630.304 | -0% | 9062.9 | 9079.6 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 12.806 | +10% | 11.6 | 37.6 | +224% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 186.723 | +1% | 185.4 | 224.3 | +21% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 193.954 | -0% | 775.0 | 810.4 | +5% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 228.949 | -0% | 3185.5 | 3198.0 | +0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 711.380 | +1% | 10722.1 | 10711.3 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7213.005 | -1% | 106694.8 | 106836.0 | +0% | 25.5 | 25.4 |  |
| sm-repeat-gap t=16 | 32.627 | 51.464 | +58% | 6.8 | 162.5 | +2306% | 2.0 | 2.6 | time WORSE, CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 117.761 | +1% | 90.4 | 244.7 | +171% | 2.0 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 123.330 | -6% | 367.7 | 502.7 | +37% | 2.3 | 2.6 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 343.758 | +2% | 3765.7 | 3882.3 | +3% | 2.9 | 2.9 |  |
| sm-repeat-gap t=100000 | 270.189 | 266.829 | -1% | 3596.3 | 3646.1 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 498.659 | -3% | 7067.4 | 7006.7 | -1% | 25.5 | 25.5 |  |

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
- sm-repeat-long t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-long t=256: CPU WORSE, RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: time WORSE, CPU WORSE, RSS WORSE
- sm-repeat-gap t=256: CPU WORSE, RSS WORSE
- sm-repeat-gap t=1024: CPU WORSE, RSS WORSE
