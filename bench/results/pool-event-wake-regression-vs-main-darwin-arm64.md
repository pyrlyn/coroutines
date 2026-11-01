# Benchmark: pool-event-wake (regression suite) vs main (darwin-arm64)

Regression check of code paths Pool does not touch (runParallel, Io group, Dispatcher with small 8-byte and large 256-byte messages), sizes 16..1M.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 7.7, median 16.0, max 56.0. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 5 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.276 | 14.015 | -2% | 14.3 | 14.0 | -2% | 1.9 | 1.9 |  |
| io-switch | 716.491 | 708.402 | -1% | 735.8 | 722.5 | -2% | 2.0 | 2.0 |  |
| sequential | 16.699 | 16.767 | +0% | 16.7 | 16.7 | +0% | 2.0 | 2.0 |  |
| sm-1thread | 15.432 | 15.300 | -1% | 15.4 | 15.3 | -1% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.029 | 0.028 | -2% | 0.0 | 0.0 | +3% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.392 | 0.400 | +2% | 0.4 | 0.4 | +2% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.483 | 0.463 | -4% | 1.8 | 1.7 | -3% | 2.1 | 2.1 |  |
| sm-parallel t=10000 | 1.751 | 1.788 | +2% | 18.8 | 19.0 | +1% | 2.8 | 2.8 |  |
| sm-parallel t=100000 | 13.154 | 13.673 | +4% | 183.3 | 184.9 | +1% | 4.8 | 4.8 |  |
| sm-parallel t=1000000 | 129.951 | 135.301 | +4% | 1775.6 | 1780.3 | +0% | 25.4 | 25.4 |  |
| sm-skew t=16 | 0.144 | 0.141 | -2% | 0.1 | 0.1 | -1% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.714 | 0.695 | -3% | 0.7 | 0.7 | -2% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.767 | 0.788 | +3% | 2.8 | 2.9 | +2% | 2.1 | 2.1 |  |
| sm-skew t=10000 | 2.667 | 2.565 | -4% | 29.1 | 29.5 | +2% | 2.7 | 2.8 |  |
| sm-skew t=100000 | 21.071 | 21.208 | +1% | 285.0 | 283.1 | -1% | 4.8 | 4.8 |  |
| sm-skew t=1000000 | 199.709 | 205.224 | +3% | 2826.6 | 2822.6 | -0% | 25.4 | 25.4 |  |
| sm-big t=16 | 0.034 | 0.033 | -1% | 0.0 | 0.0 | -2% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.502 | 0.764 | +52% | 0.5 | 0.8 | +47% | 2.1 | 2.1 | time ~noise, CPU ~noise |
| sm-big t=1024 | 1.094 | 1.059 | -3% | 3.2 | 2.9 | -10% | 2.6 | 2.6 |  |
| sm-big t=10000 | 4.421 | 4.177 | -6% | 24.5 | 23.9 | -3% | 7.3 | 7.2 |  |
| sm-big t=100000 | 33.860 | 34.880 | +3% | 232.2 | 228.0 | -2% | 50.6 | 50.6 |  |
| sm-big t=1000000 | 267.920 | 229.530 | -14% | 2287.5 | 2267.8 | -1% | 483.2 | 483.2 | time ~noise |
| io-group t=16 | 0.300 | 0.324 | +8% | 1.1 | 1.0 | -6% | 2.6 | 2.6 |  |
| io-group t=256 | 1.331 | 1.485 | +12% | 3.3 | 4.3 | +32% | 3.1 | 3.2 | time ~noise, CPU ~noise |
| io-group t=1024 | 4.825 | 5.492 | +14% | 14.6 | 18.3 | +25% | 3.4 | 3.1 | time WORSE, CPU WORSE, RSS better |
| io-group t=10000 | 27.991 | 28.729 | +3% | 102.6 | 99.9 | -3% | 3.8 | 3.5 |  |
| io-group t=100000 | 420.797 | 446.538 | +6% | 796.8 | 824.9 | +4% | 10.5 | 12.3 | RSS ~noise |
| io-group t=1000000 | 3361.689 | 3240.957 | -4% | 10546.8 | 10476.0 | -1% | 4.7 | 3.1 | RSS ~noise |
| io-dispatch t=16 | 0.295 | 0.270 | -9% | 1.8 | 1.9 | +8% | 2.7 | 2.7 |  |
| io-dispatch t=256 | 0.411 | 0.416 | +1% | 4.9 | 4.7 | -5% | 2.8 | 2.8 |  |
| io-dispatch t=1024 | 2.635 | 2.985 | +13% | 16.8 | 19.2 | +15% | 2.7 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 42.058 | 31.009 | -26% | 232.6 | 182.3 | -22% | 2.7 | 2.7 | time better, CPU better |
| io-dispatch t=100000 | 350.528 | 328.256 | -6% | 1990.8 | 1889.3 | -5% | 2.8 | 2.7 |  |
| io-dispatch t=1000000 | 2285.709 | 2799.307 | +22% | 7576.9 | 7532.8 | -1% | 2.8 | 2.8 | time ~noise |
| io-dispatch-big t=16 | 0.314 | 0.323 | +3% | 2.2 | 1.7 | -22% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=256 | 1.391 | 1.272 | -9% | 8.1 | 6.8 | -17% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=1024 | 5.062 | 5.775 | +14% | 27.2 | 31.2 | +15% | 2.8 | 2.8 | time WORSE, CPU WORSE |
| io-dispatch-big t=10000 | 16.279 | 13.224 | -19% | 74.5 | 59.0 | -21% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=100000 | 215.206 | 279.871 | +30% | 154.3 | 687.5 | +345% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=1000000 | 3106.394 | 2943.935 | -5% | 10527.5 | 9406.1 | -11% | 2.8 | 2.8 | CPU ~noise |

## Regressions vs main (WORSE)

- io-group t=1024: time WORSE, CPU WORSE
- io-dispatch-big t=1024: time WORSE, CPU WORSE
