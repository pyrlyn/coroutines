# Benchmark: pool-spin-bounded (regression suite) vs main (darwin-arm64)

Regression check of code paths Pool does not touch (runParallel, Io group, Dispatcher with small 8-byte and large 256-byte messages), sizes 16..1M.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 7.7, median 16.0, max 56.0. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 5 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.276 | 14.289 | +0% | 14.3 | 14.3 | +0% | 1.9 | 1.9 |  |
| io-switch | 716.491 | 726.769 | +1% | 735.8 | 746.7 | +1% | 2.0 | 2.0 |  |
| sequential | 16.699 | 16.810 | +1% | 16.7 | 16.8 | +1% | 2.0 | 1.9 |  |
| sm-1thread | 15.432 | 15.450 | +0% | 15.4 | 15.4 | +0% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.029 | 0.027 | -4% | 0.0 | 0.0 | +0% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.392 | 0.392 | -0% | 0.4 | 0.4 | +1% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.483 | 0.504 | +4% | 1.8 | 1.8 | +3% | 2.1 | 2.1 |  |
| sm-parallel t=10000 | 1.751 | 1.591 | -9% | 18.8 | 19.5 | +4% | 2.8 | 2.8 |  |
| sm-parallel t=100000 | 13.154 | 13.103 | -0% | 183.3 | 184.6 | +1% | 4.8 | 4.8 |  |
| sm-parallel t=1000000 | 129.951 | 131.438 | +1% | 1775.6 | 1789.2 | +1% | 25.4 | 25.5 |  |
| sm-skew t=16 | 0.144 | 0.139 | -3% | 0.1 | 0.1 | -3% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.714 | 0.729 | +2% | 0.7 | 0.7 | +2% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.767 | 0.748 | -2% | 2.8 | 2.8 | -2% | 2.1 | 2.1 |  |
| sm-skew t=10000 | 2.667 | 2.478 | -7% | 29.1 | 29.8 | +2% | 2.7 | 2.8 |  |
| sm-skew t=100000 | 21.071 | 20.647 | -2% | 285.0 | 282.1 | -1% | 4.8 | 4.8 |  |
| sm-skew t=1000000 | 199.709 | 203.473 | +2% | 2826.6 | 2781.5 | -2% | 25.4 | 25.4 |  |
| sm-big t=16 | 0.034 | 0.034 | +0% | 0.0 | 0.0 | +5% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.502 | 0.511 | +2% | 0.5 | 0.5 | +2% | 2.1 | 2.1 |  |
| sm-big t=1024 | 1.094 | 1.029 | -6% | 3.2 | 2.9 | -11% | 2.6 | 2.6 | CPU ~noise |
| sm-big t=10000 | 4.421 | 5.527 | +25% | 24.5 | 24.1 | -1% | 7.3 | 7.2 | time ~noise |
| sm-big t=100000 | 33.860 | 30.497 | -10% | 232.2 | 227.3 | -2% | 50.6 | 50.6 |  |
| sm-big t=1000000 | 267.920 | 236.583 | -12% | 2287.5 | 2251.7 | -2% | 483.2 | 483.2 | time better |
| io-group t=16 | 0.300 | 0.244 | -19% | 1.1 | 0.8 | -24% | 2.6 | 2.5 | time ~noise, CPU ~noise |
| io-group t=256 | 1.331 | 1.367 | +3% | 3.3 | 4.1 | +25% | 3.1 | 3.2 | CPU ~noise |
| io-group t=1024 | 4.825 | 5.298 | +10% | 14.6 | 17.9 | +23% | 3.4 | 3.5 | CPU ~noise |
| io-group t=10000 | 27.991 | 34.210 | +22% | 102.6 | 108.6 | +6% | 3.8 | 5.2 | time ~noise, RSS ~noise |
| io-group t=100000 | 420.797 | 425.584 | +1% | 796.8 | 787.9 | -1% | 10.5 | 11.4 |  |
| io-group t=1000000 | 3361.689 | 3266.197 | -3% | 10546.8 | 10615.3 | +1% | 4.7 | 3.8 | RSS ~noise |
| io-dispatch t=16 | 0.295 | 0.257 | -13% | 1.8 | 2.3 | +33% | 2.7 | 2.8 | time better, CPU ~noise |
| io-dispatch t=256 | 0.411 | 0.361 | -12% | 4.9 | 3.6 | -26% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 2.635 | 2.592 | -2% | 16.8 | 16.2 | -4% | 2.7 | 2.8 |  |
| io-dispatch t=10000 | 42.058 | 32.174 | -24% | 232.6 | 192.5 | -17% | 2.7 | 2.8 | time better, CPU better |
| io-dispatch t=100000 | 350.528 | 372.395 | +6% | 1990.8 | 2070.6 | +4% | 2.8 | 2.7 |  |
| io-dispatch t=1000000 | 2285.709 | 2444.288 | +7% | 7576.9 | 6816.8 | -10% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=16 | 0.314 | 0.323 | +3% | 2.2 | 1.9 | -14% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=256 | 1.391 | 0.917 | -34% | 8.1 | 4.9 | -40% | 2.8 | 2.8 | time better, CPU ~noise |
| io-dispatch-big t=1024 | 5.062 | 4.331 | -14% | 27.2 | 23.4 | -14% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=10000 | 16.279 | 33.581 | +106% | 74.5 | 181.3 | +143% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=100000 | 215.206 | 228.982 | +6% | 154.3 | 550.4 | +257% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=1000000 | 3106.394 | 3505.738 | +13% | 10527.5 | 10668.3 | +1% | 2.8 | 2.8 | time ~noise |

## Regressions vs main (WORSE)

- none
