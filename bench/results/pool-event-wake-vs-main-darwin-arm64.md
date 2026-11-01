# Benchmark: pool-event-wake (no spin + cap_wake) vs main (darwin-arm64)

Idle threads sleep on the futex at once; run wakes min(threads-1, chunks-1) threads.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 5.6, median 34.1, max 267.8. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 12.729 | 12.312 | -3% | 12.7 | 13.0 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 189.209 | 192.134 | +2% | 189.0 | 192.6 | +2% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat t=1024 | 225.741 | 215.462 | -5% | 842.2 | 884.8 | +5% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat t=10000 | 309.592 | 305.503 | -1% | 3770.9 | 3825.6 | +1% | 2.9 | 2.8 |  |
| sm-repeat t=100000 | 260.883 | 262.634 | +1% | 3623.8 | 3661.7 | +1% | 5.0 | 4.9 |  |
| sm-repeat t=1000000 | 497.602 | 495.683 | -0% | 7039.6 | 7074.7 | +0% | 25.5 | 25.5 |  |
| sm-repeat-skew t=16 | 73.497 | 81.880 | +11% | 72.8 | 71.3 | -2% | 2.0 | 2.4 | time ~noise, RSS WORSE |
| sm-repeat-skew t=256 | 371.213 | 371.732 | +0% | 370.9 | 372.0 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 412.720 | 408.813 | -1% | 1479.9 | 1529.2 | +3% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-skew t=10000 | 477.177 | 507.488 | +6% | 5814.1 | 5847.6 | +1% | 3.1 | 2.8 |  |
| sm-repeat-skew t=100000 | 389.500 | 390.645 | +0% | 5662.5 | 5658.8 | -0% | 4.9 | 4.9 |  |
| sm-repeat-skew t=1000000 | 762.909 | 749.535 | -2% | 11286.2 | 11486.6 | +2% | 25.4 | 25.5 |  |
| sm-repeat-big t=16 | 14.524 | 14.732 | +1% | 14.5 | 15.3 | +5% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=256 | 234.115 | 234.953 | +0% | 234.1 | 235.4 | +1% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 269.110 | 262.373 | -3% | 1023.8 | 1080.0 | +5% | 2.7 | 3.0 | RSS WORSE |
| sm-repeat-big t=10000 | 348.163 | 332.807 | -4% | 4501.9 | 4469.2 | -1% | 7.5 | 7.4 |  |
| sm-repeat-big t=100000 | 309.188 | 310.128 | +0% | 4519.0 | 4515.0 | -0% | 50.7 | 50.7 |  |
| sm-repeat-big t=1000000 | 631.171 | 630.782 | -0% | 9062.9 | 9070.8 | +0% | 483.2 | 483.3 |  |
| sm-repeat-long t=16 | 11.604 | 11.777 | +1% | 11.6 | 12.2 | +5% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=256 | 185.381 | 185.038 | -0% | 185.4 | 185.6 | +0% | 2.0 | 2.3 | RSS WORSE |
| sm-repeat-long t=1024 | 194.790 | 194.636 | -0% | 775.0 | 779.6 | +1% | 2.2 | 2.6 | RSS WORSE |
| sm-repeat-long t=10000 | 229.643 | 229.411 | -0% | 3185.5 | 3190.1 | +0% | 2.8 | 2.9 |  |
| sm-repeat-long t=100000 | 705.200 | 707.629 | +0% | 10722.1 | 10717.1 | -0% | 4.8 | 4.9 |  |
| sm-repeat-long t=1000000 | 7265.314 | 7209.039 | -1% | 106694.8 | 106807.1 | +0% | 25.5 | 25.5 |  |
| sm-repeat-gap t=16 | 32.627 | 32.977 | +1% | 6.8 | 7.6 | +12% | 2.0 | 2.3 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=256 | 116.486 | 116.623 | +0% | 90.4 | 90.9 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 130.673 | 125.736 | -4% | 367.7 | 380.7 | +4% | 2.3 | 2.6 | RSS WORSE |
| sm-repeat-gap t=10000 | 337.446 | 332.024 | -2% | 3765.7 | 3795.0 | +1% | 2.9 | 2.8 |  |
| sm-repeat-gap t=100000 | 270.189 | 275.404 | +2% | 3596.3 | 3620.2 | +1% | 4.9 | 4.9 |  |
| sm-repeat-gap t=1000000 | 511.932 | 486.754 | -5% | 7067.4 | 7114.8 | +1% | 25.5 | 25.5 |  |

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
