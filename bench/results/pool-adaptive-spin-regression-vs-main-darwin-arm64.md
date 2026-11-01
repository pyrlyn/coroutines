# Benchmark: pool-adaptive-spin (regression suite) vs main (darwin-arm64)

Regression check of code paths Pool does not touch (runParallel, Io group, Dispatcher with small 8-byte and large 256-byte messages), sizes 16..1M.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 7.7, median 16.0, max 56.0. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 5 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.276 | 14.211 | -0% | 14.3 | 14.1 | -1% | 1.9 | 1.9 |  |
| io-switch | 716.491 | 753.821 | +5% | 735.8 | 774.3 | +5% | 2.0 | 2.0 |  |
| sequential | 16.699 | 16.738 | +0% | 16.7 | 16.7 | +0% | 2.0 | 1.9 |  |
| sm-1thread | 15.432 | 15.561 | +1% | 15.4 | 15.5 | +1% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.029 | 0.029 | -0% | 0.0 | 0.0 | +3% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.392 | 0.409 | +4% | 0.4 | 0.4 | +6% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.483 | 0.484 | +0% | 1.8 | 1.8 | -0% | 2.1 | 2.1 |  |
| sm-parallel t=10000 | 1.751 | 1.770 | +1% | 18.8 | 18.8 | -0% | 2.8 | 2.8 |  |
| sm-parallel t=100000 | 13.154 | 13.150 | -0% | 183.3 | 183.0 | -0% | 4.8 | 4.8 |  |
| sm-parallel t=1000000 | 129.951 | 129.572 | -0% | 1775.6 | 1792.1 | +1% | 25.4 | 25.4 |  |
| sm-skew t=16 | 0.144 | 0.144 | -0% | 0.1 | 0.1 | +0% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.714 | 0.754 | +6% | 0.7 | 0.8 | +5% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.767 | 0.751 | -2% | 2.8 | 2.8 | -1% | 2.1 | 2.1 |  |
| sm-skew t=10000 | 2.667 | 2.607 | -2% | 29.1 | 29.2 | +0% | 2.7 | 2.8 |  |
| sm-skew t=100000 | 21.071 | 20.840 | -1% | 285.0 | 283.8 | -0% | 4.8 | 4.8 |  |
| sm-skew t=1000000 | 199.709 | 203.767 | +2% | 2826.6 | 2804.0 | -1% | 25.4 | 25.4 |  |
| sm-big t=16 | 0.034 | 0.038 | +12% | 0.0 | 0.0 | +7% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.502 | 0.634 | +26% | 0.5 | 0.6 | +14% | 2.1 | 2.1 | time ~noise |
| sm-big t=1024 | 1.094 | 1.104 | +1% | 3.2 | 3.1 | -5% | 2.6 | 2.6 |  |
| sm-big t=10000 | 4.421 | 4.493 | +2% | 24.5 | 24.5 | +0% | 7.3 | 7.2 |  |
| sm-big t=100000 | 33.860 | 27.068 | -20% | 232.2 | 229.7 | -1% | 50.6 | 50.6 | time ~noise |
| sm-big t=1000000 | 267.920 | 242.083 | -10% | 2287.5 | 2261.1 | -1% | 483.2 | 483.2 |  |
| io-group t=16 | 0.300 | 0.263 | -12% | 1.1 | 0.9 | -12% | 2.6 | 2.6 | time ~noise |
| io-group t=256 | 1.331 | 1.327 | -0% | 3.3 | 4.6 | +42% | 3.1 | 3.3 | CPU ~noise |
| io-group t=1024 | 4.825 | 5.205 | +8% | 14.6 | 16.2 | +11% | 3.4 | 3.5 | CPU WORSE |
| io-group t=10000 | 27.991 | 29.007 | +4% | 102.6 | 103.1 | +0% | 3.8 | 5.2 | RSS WORSE |
| io-group t=100000 | 420.797 | 464.498 | +10% | 796.8 | 809.7 | +2% | 10.5 | 10.4 | time WORSE |
| io-group t=1000000 | 3361.689 | 3325.651 | -1% | 10546.8 | 10602.6 | +1% | 4.7 | 3.9 | RSS ~noise |
| io-dispatch t=16 | 0.295 | 0.325 | +10% | 1.8 | 1.5 | -17% | 2.7 | 2.7 | CPU ~noise |
| io-dispatch t=256 | 0.411 | 0.355 | -14% | 4.9 | 2.7 | -44% | 2.8 | 2.7 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 2.635 | 3.523 | +34% | 16.8 | 19.7 | +17% | 2.7 | 2.7 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 42.058 | 31.215 | -26% | 232.6 | 180.3 | -22% | 2.7 | 2.7 | time better, CPU better |
| io-dispatch t=100000 | 350.528 | 362.942 | +4% | 1990.8 | 2082.1 | +5% | 2.8 | 2.7 |  |
| io-dispatch t=1000000 | 2285.709 | 2262.939 | -1% | 7576.9 | 6383.5 | -16% | 2.8 | 2.7 | CPU ~noise |
| io-dispatch-big t=16 | 0.314 | 0.284 | -10% | 2.2 | 2.1 | -4% | 2.8 | 2.8 |  |
| io-dispatch-big t=256 | 1.391 | 1.329 | -4% | 8.1 | 7.7 | -5% | 2.8 | 2.8 |  |
| io-dispatch-big t=1024 | 5.062 | 4.287 | -15% | 27.2 | 21.9 | -19% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=10000 | 16.279 | 20.219 | +24% | 74.5 | 91.3 | +23% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=100000 | 215.206 | 378.732 | +76% | 154.3 | 2016.1 | +1206% | 2.8 | 2.8 | time WORSE, CPU WORSE |
| io-dispatch-big t=1000000 | 3106.394 | 2728.732 | -12% | 10527.5 | 7697.3 | -27% | 2.8 | 2.8 | time ~noise, CPU ~noise |

## Regressions vs main (WORSE)

- io-group t=1024: CPU WORSE
- io-group t=10000: RSS WORSE
- io-group t=100000: time WORSE
- io-dispatch-big t=100000: time WORSE, CPU WORSE
