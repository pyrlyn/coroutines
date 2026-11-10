# Benchmark: pool-event-wake on main 65b74e7 vs main (darwin-arm64)

Event-only wake + cap_wake (#16 after merging main 65b74e7). Sizes 16..1M, 9 interleaved runs.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 16.1, median 29.4, max 114.4. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 9 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 13.662 | 13.726 | +0% | 13.6 | 14.3 | +5% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=64 | 49.300 | 49.122 | -0% | 49.2 | 49.8 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 200.703 | 201.955 | +1% | 199.2 | 200.1 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=1024 | 226.466 | 217.653 | -4% | 853.0 | 896.9 | +5% | 2.3 | 2.7 | RSS WORSE |
| sm-repeat t=10000 | 331.803 | 314.947 | -5% | 3931.4 | 3859.6 | -2% | 3.1 | 2.9 |  |
| sm-repeat t=100000 | 273.670 | 274.017 | +0% | 3572.4 | 3615.8 | +1% | 5.1 | 4.9 |  |
| sm-repeat t=1000000 | 537.148 | 541.939 | +1% | 7087.0 | 7005.5 | -1% | 25.6 | 25.5 |  |
| sm-repeat-skew t=16 | 69.342 | 69.140 | -0% | 68.6 | 68.8 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=64 | 106.074 | 106.340 | +0% | 105.8 | 106.7 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=256 | 353.960 | 351.941 | -1% | 351.9 | 351.8 | -0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 399.906 | 391.062 | -2% | 1444.6 | 1498.0 | +4% | 2.3 | 2.7 | RSS WORSE |
| sm-repeat-skew t=10000 | 499.887 | 493.835 | -1% | 5977.0 | 5924.1 | -1% | 3.0 | 2.9 |  |
| sm-repeat-skew t=100000 | 430.195 | 433.374 | +1% | 5646.9 | 5637.6 | -0% | 5.0 | 4.9 |  |
| sm-repeat-skew t=1000000 | 812.750 | 808.765 | -0% | 11254.6 | 11270.8 | +0% | 25.5 | 25.5 |  |
| sm-repeat-big t=16 | 15.035 | 15.355 | +2% | 15.0 | 15.8 | +5% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=64 | 56.594 | 57.331 | +1% | 56.4 | 57.7 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=256 | 223.124 | 227.354 | +2% | 222.5 | 227.1 | +2% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 254.804 | 244.542 | -4% | 957.5 | 999.3 | +4% | 2.8 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 358.039 | 338.409 | -5% | 4155.9 | 4087.2 | -2% | 7.6 | 7.4 |  |
| sm-repeat-big t=100000 | 306.060 | 308.028 | +1% | 4045.5 | 4045.0 | -0% | 50.9 | 50.7 |  |
| sm-repeat-big t=1000000 | 654.177 | 635.170 | -3% | 8084.7 | 8082.2 | -0% | 483.4 | 483.2 |  |
| sm-repeat-long t=16 | 12.499 | 12.586 | +1% | 12.5 | 13.3 | +6% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=64 | 49.400 | 49.830 | +1% | 49.4 | 50.8 | +3% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=256 | 197.357 | 196.320 | -1% | 196.5 | 196.5 | +0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=1024 | 198.183 | 196.843 | -1% | 786.2 | 787.8 | +0% | 2.2 | 2.7 | RSS WORSE |
| sm-repeat-long t=10000 | 236.041 | 229.705 | -3% | 3230.4 | 3235.2 | +0% | 3.0 | 2.9 |  |
| sm-repeat-long t=100000 | 735.234 | 733.036 | -0% | 10712.2 | 10731.8 | +0% | 5.0 | 4.9 |  |
| sm-repeat-long t=1000000 | 7714.864 | 7709.215 | -0% | 106377.9 | 106578.2 | +0% | 25.6 | 25.5 |  |
| sm-repeat-gap t=16 | 31.522 | 31.774 | +1% | 6.0 | 6.7 | +12% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=64 | 46.050 | 46.223 | +0% | 20.6 | 21.3 | +3% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=256 | 107.591 | 108.833 | +1% | 81.1 | 83.8 | +3% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 117.221 | 113.151 | -3% | 344.5 | 358.8 | +4% | 2.3 | 2.7 | RSS WORSE |
| sm-repeat-gap t=10000 | 360.891 | 342.917 | -5% | 3925.4 | 3821.1 | -3% | 3.1 | 2.9 |  |
| sm-repeat-gap t=100000 | 287.262 | 281.021 | -2% | 3592.4 | 3596.6 | +0% | 5.1 | 4.9 |  |
| sm-repeat-gap t=1000000 | 539.358 | 540.051 | +0% | 7033.0 | 7063.0 | +0% | 25.6 | 25.5 |  |

## Regressions vs main (WORSE)

- sm-repeat t=16: RSS WORSE
- sm-repeat t=64: RSS WORSE
- sm-repeat t=256: RSS WORSE
- sm-repeat t=1024: RSS WORSE
- sm-repeat-skew t=16: RSS WORSE
- sm-repeat-skew t=64: RSS WORSE
- sm-repeat-skew t=256: RSS WORSE
- sm-repeat-skew t=1024: RSS WORSE
- sm-repeat-big t=16: RSS WORSE
- sm-repeat-big t=64: RSS WORSE
- sm-repeat-big t=256: RSS WORSE
- sm-repeat-big t=1024: RSS WORSE
- sm-repeat-long t=16: RSS WORSE
- sm-repeat-long t=64: RSS WORSE
- sm-repeat-long t=256: RSS WORSE
- sm-repeat-long t=1024: RSS WORSE
- sm-repeat-gap t=16: CPU WORSE, RSS WORSE
- sm-repeat-gap t=64: RSS WORSE
- sm-repeat-gap t=256: RSS WORSE
- sm-repeat-gap t=1024: RSS WORSE
