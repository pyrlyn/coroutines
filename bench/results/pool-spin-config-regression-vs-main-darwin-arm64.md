# Benchmark: pool-spin-config (regression suite) vs main (darwin-arm64)

Regression check of code paths Pool does not touch (runParallel, Io group, Dispatcher with small 8-byte and large 256-byte messages), sizes 16..1M.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 7.7, median 16.0, max 56.0. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 5 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.276 | 14.252 | -0% | 14.3 | 14.3 | -0% | 1.9 | 1.9 |  |
| io-switch | 716.491 | 718.931 | +0% | 735.8 | 736.4 | +0% | 2.0 | 2.0 |  |
| sequential | 16.699 | 16.827 | +1% | 16.7 | 16.8 | +1% | 2.0 | 1.9 |  |
| sm-1thread | 15.432 | 15.570 | +1% | 15.4 | 15.4 | -0% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.029 | 0.028 | -2% | 0.0 | 0.0 | +6% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.392 | 0.405 | +3% | 0.4 | 0.4 | +4% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.483 | 0.483 | +0% | 1.8 | 1.8 | +0% | 2.1 | 2.1 |  |
| sm-parallel t=10000 | 1.751 | 1.732 | -1% | 18.8 | 19.4 | +3% | 2.8 | 2.8 |  |
| sm-parallel t=100000 | 13.154 | 12.986 | -1% | 183.3 | 182.3 | -1% | 4.8 | 4.8 |  |
| sm-parallel t=1000000 | 129.951 | 136.717 | +5% | 1775.6 | 1768.5 | -0% | 25.4 | 25.4 |  |
| sm-skew t=16 | 0.144 | 0.134 | -7% | 0.1 | 0.1 | -6% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.714 | 0.702 | -2% | 0.7 | 0.7 | -2% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.767 | 0.776 | +1% | 2.8 | 2.8 | +0% | 2.1 | 2.1 |  |
| sm-skew t=10000 | 2.667 | 2.657 | -0% | 29.1 | 29.5 | +1% | 2.7 | 2.7 |  |
| sm-skew t=100000 | 21.071 | 21.102 | +0% | 285.0 | 285.4 | +0% | 4.8 | 4.8 |  |
| sm-skew t=1000000 | 199.709 | 209.926 | +5% | 2826.6 | 2828.9 | +0% | 25.4 | 25.4 |  |
| sm-big t=16 | 0.034 | 0.034 | +0% | 0.0 | 0.0 | +0% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.502 | 0.793 | +58% | 0.5 | 0.8 | +55% | 2.1 | 2.1 | time WORSE, CPU WORSE |
| sm-big t=1024 | 1.094 | 1.153 | +5% | 3.2 | 3.0 | -8% | 2.6 | 2.6 |  |
| sm-big t=10000 | 4.421 | 3.785 | -14% | 24.5 | 24.2 | -1% | 7.3 | 7.2 | time ~noise |
| sm-big t=100000 | 33.860 | 33.708 | -0% | 232.2 | 229.0 | -1% | 50.6 | 50.6 |  |
| sm-big t=1000000 | 267.920 | 233.580 | -13% | 2287.5 | 2255.8 | -1% | 483.2 | 483.2 | time better |
| io-group t=16 | 0.300 | 0.276 | -8% | 1.1 | 1.0 | -8% | 2.6 | 2.6 |  |
| io-group t=256 | 1.331 | 1.496 | +12% | 3.3 | 4.9 | +50% | 3.1 | 3.0 | time ~noise, CPU ~noise |
| io-group t=1024 | 4.825 | 4.910 | +2% | 14.6 | 15.0 | +3% | 3.4 | 4.0 | RSS WORSE |
| io-group t=10000 | 27.991 | 33.792 | +21% | 102.6 | 112.2 | +9% | 3.8 | 4.9 | time ~noise, RSS ~noise |
| io-group t=100000 | 420.797 | 431.034 | +2% | 796.8 | 792.5 | -1% | 10.5 | 9.8 |  |
| io-group t=1000000 | 3361.689 | 3348.462 | -0% | 10546.8 | 10790.3 | +2% | 4.7 | 3.4 | RSS ~noise |
| io-dispatch t=16 | 0.295 | 0.302 | +2% | 1.8 | 1.7 | -5% | 2.7 | 2.8 |  |
| io-dispatch t=256 | 0.411 | 0.636 | +55% | 4.9 | 4.0 | -18% | 2.8 | 2.7 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 2.635 | 4.076 | +55% | 16.8 | 24.2 | +44% | 2.7 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 42.058 | 33.572 | -20% | 232.6 | 189.5 | -19% | 2.7 | 2.8 | time better, CPU better |
| io-dispatch t=100000 | 350.528 | 361.731 | +3% | 1990.8 | 2057.1 | +3% | 2.8 | 2.7 |  |
| io-dispatch t=1000000 | 2285.709 | 2435.241 | +7% | 7576.9 | 8814.7 | +16% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=16 | 0.314 | 0.257 | -18% | 2.2 | 1.6 | -26% | 2.8 | 2.8 | time better, CPU ~noise |
| io-dispatch-big t=256 | 1.391 | 0.945 | -32% | 8.1 | 7.1 | -12% | 2.8 | 2.8 | time better, CPU ~noise |
| io-dispatch-big t=1024 | 5.062 | 3.844 | -24% | 27.2 | 20.7 | -24% | 2.8 | 2.8 | time better, CPU better |
| io-dispatch-big t=10000 | 16.279 | 15.289 | -6% | 74.5 | 67.6 | -9% | 2.8 | 2.8 |  |
| io-dispatch-big t=100000 | 215.206 | 219.425 | +2% | 154.3 | 137.7 | -11% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=1000000 | 3106.394 | 2801.629 | -10% | 10527.5 | 9231.3 | -12% | 2.8 | 2.8 | CPU ~noise |

## Regressions vs main (WORSE)

- sm-big t=256: time WORSE, CPU WORSE
- io-group t=1024: RSS WORSE
