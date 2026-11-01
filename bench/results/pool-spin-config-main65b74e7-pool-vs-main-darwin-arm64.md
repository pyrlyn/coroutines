# Benchmark: pool-spin-config default on main 65b74e7 vs main (darwin-arm64)

Adaptive spin + cap_wake (#15 after merging main 65b74e7). 9 interleaved runs.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 16.1, median 29.4, max 114.4. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 9 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-repeat t=16 | 13.662 | 14.070 | +3% | 13.6 | 14.6 | +7% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=64 | 49.300 | 49.502 | +0% | 49.2 | 50.1 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=256 | 200.703 | 198.852 | -1% | 199.2 | 199.0 | -0% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat t=1024 | 226.466 | 208.111 | -8% | 853.0 | 874.1 | +2% | 2.3 | 2.5 | RSS WORSE |
| sm-repeat t=10000 | 331.803 | 313.172 | -6% | 3931.4 | 3852.1 | -2% | 3.1 | 2.9 |  |
| sm-repeat t=100000 | 273.670 | 278.191 | +2% | 3572.4 | 3625.2 | +1% | 5.1 | 4.9 |  |
| sm-repeat t=1000000 | 537.148 | 545.821 | +2% | 7087.0 | 7039.8 | -1% | 25.6 | 25.5 |  |
| sm-repeat-skew t=16 | 69.342 | 69.175 | -0% | 68.6 | 69.3 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=64 | 106.074 | 106.004 | -0% | 105.8 | 106.5 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=256 | 353.960 | 346.279 | -2% | 351.9 | 346.5 | -2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-skew t=1024 | 399.906 | 390.219 | -2% | 1444.6 | 1495.7 | +4% | 2.3 | 2.7 | RSS WORSE |
| sm-repeat-skew t=10000 | 499.887 | 489.844 | -2% | 5977.0 | 5963.6 | -0% | 3.0 | 2.9 |  |
| sm-repeat-skew t=100000 | 430.195 | 436.241 | +1% | 5646.9 | 5613.2 | -1% | 5.0 | 4.9 |  |
| sm-repeat-skew t=1000000 | 812.750 | 801.089 | -1% | 11254.6 | 11223.5 | -0% | 25.5 | 25.5 |  |
| sm-repeat-big t=16 | 15.035 | 15.127 | +1% | 15.0 | 15.7 | +5% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=64 | 56.594 | 57.194 | +1% | 56.4 | 57.8 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-big t=256 | 223.124 | 225.637 | +1% | 222.5 | 224.8 | +1% | 2.1 | 2.5 | RSS WORSE |
| sm-repeat-big t=1024 | 254.804 | 241.271 | -5% | 957.5 | 1008.6 | +5% | 2.8 | 3.1 | RSS WORSE |
| sm-repeat-big t=10000 | 358.039 | 338.951 | -5% | 4155.9 | 4084.7 | -2% | 7.6 | 7.5 |  |
| sm-repeat-big t=100000 | 306.060 | 303.541 | -1% | 4045.5 | 4030.1 | -0% | 50.9 | 50.7 |  |
| sm-repeat-big t=1000000 | 654.177 | 638.670 | -2% | 8084.7 | 8119.0 | +0% | 483.4 | 483.2 |  |
| sm-repeat-long t=16 | 12.499 | 12.727 | +2% | 12.5 | 13.4 | +7% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=64 | 49.400 | 49.499 | +0% | 49.4 | 50.2 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=256 | 197.357 | 198.115 | +0% | 196.5 | 197.5 | +1% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-long t=1024 | 198.183 | 195.559 | -1% | 786.2 | 783.5 | -0% | 2.2 | 2.7 | RSS WORSE |
| sm-repeat-long t=10000 | 236.041 | 231.153 | -2% | 3230.4 | 3221.5 | -0% | 3.0 | 2.9 |  |
| sm-repeat-long t=100000 | 735.234 | 737.537 | +0% | 10712.2 | 10619.2 | -1% | 5.0 | 4.9 |  |
| sm-repeat-long t=1000000 | 7714.864 | 7641.252 | -1% | 106377.9 | 106207.3 | -0% | 25.6 | 25.5 |  |
| sm-repeat-gap t=16 | 31.522 | 31.861 | +1% | 6.0 | 6.8 | +13% | 2.0 | 2.4 | CPU WORSE, RSS WORSE |
| sm-repeat-gap t=64 | 46.050 | 46.191 | +0% | 20.6 | 21.4 | +4% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=256 | 107.591 | 108.193 | +1% | 81.1 | 83.1 | +2% | 2.0 | 2.4 | RSS WORSE |
| sm-repeat-gap t=1024 | 117.221 | 111.781 | -5% | 344.5 | 356.1 | +3% | 2.3 | 2.7 | RSS WORSE |
| sm-repeat-gap t=10000 | 360.891 | 347.387 | -4% | 3925.4 | 3818.5 | -3% | 3.1 | 2.9 |  |
| sm-repeat-gap t=100000 | 287.262 | 279.207 | -3% | 3592.4 | 3587.9 | -0% | 5.1 | 4.9 |  |
| sm-repeat-gap t=1000000 | 539.358 | 543.311 | +1% | 7033.0 | 7065.7 | +0% | 25.6 | 25.5 |  |

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
