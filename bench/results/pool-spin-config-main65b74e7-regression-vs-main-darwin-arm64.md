# Benchmark: pool-spin-config on main 65b74e7 (regression suite) vs main (darwin-arm64)

runParallel, Io group, Dispatcher small/large messages; 7 interleaved runs.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 47.7, median 57.3, max 80.4. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.543 | 14.621 | +1% | 14.4 | 14.4 | -0% | 2.0 | 2.0 |  |
| io-switch | 739.973 | 772.036 | +4% | 754.9 | 783.8 | +4% | 2.0 | 2.0 |  |
| sequential | 17.264 | 17.080 | -1% | 17.0 | 17.0 | -0% | 2.0 | 2.0 |  |
| sm-1thread | 15.636 | 15.472 | -1% | 15.6 | 15.5 | -1% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.031 | 0.031 | -1% | 0.0 | 0.0 | +6% | 2.0 | 2.0 |  |
| sm-parallel t=64 | 0.105 | 0.102 | -3% | 0.1 | 0.1 | +1% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.442 | 0.435 | -2% | 0.4 | 0.4 | +0% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.470 | 0.480 | +2% | 1.8 | 1.8 | +1% | 2.1 | 2.2 |  |
| sm-parallel t=10000 | 1.626 | 1.611 | -1% | 19.9 | 20.1 | +1% | 2.9 | 2.9 |  |
| sm-parallel t=100000 | 13.788 | 13.526 | -2% | 182.8 | 180.2 | -1% | 4.9 | 5.0 |  |
| sm-parallel t=1000000 | 134.064 | 134.356 | +0% | 1773.3 | 1773.4 | +0% | 25.5 | 25.5 |  |
| sm-skew t=16 | 0.141 | 0.142 | +1% | 0.1 | 0.1 | +1% | 2.0 | 2.0 |  |
| sm-skew t=64 | 0.211 | 0.228 | +8% | 0.2 | 0.2 | +4% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.705 | 0.734 | +4% | 0.7 | 0.7 | +5% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.809 | 0.827 | +2% | 3.0 | 3.0 | +0% | 2.1 | 2.2 |  |
| sm-skew t=10000 | 2.768 | 2.533 | -8% | 30.1 | 30.0 | -0% | 2.8 | 2.8 |  |
| sm-skew t=100000 | 21.499 | 21.784 | +1% | 284.6 | 283.6 | -0% | 4.9 | 4.9 |  |
| sm-skew t=1000000 | 213.001 | 215.292 | +1% | 2801.6 | 2780.1 | -1% | 25.5 | 25.5 |  |
| sm-big t=16 | 0.031 | 0.032 | +2% | 0.0 | 0.0 | +5% | 2.0 | 2.0 |  |
| sm-big t=64 | 0.112 | 0.115 | +3% | 0.1 | 0.1 | +7% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.447 | 0.452 | +1% | 0.5 | 0.5 | +2% | 2.1 | 2.1 |  |
| sm-big t=1024 | 0.545 | 0.535 | -2% | 2.0 | 2.0 | -1% | 2.6 | 2.6 |  |
| sm-big t=10000 | 2.073 | 2.087 | +1% | 21.7 | 21.7 | +0% | 7.4 | 7.5 |  |
| sm-big t=100000 | 18.354 | 18.174 | -1% | 206.6 | 205.7 | -0% | 50.7 | 50.8 |  |
| sm-big t=1000000 | 179.323 | 185.543 | +3% | 2048.8 | 2046.6 | -0% | 483.3 | 483.3 |  |
| io-group t=16 | 0.207 | 0.184 | -11% | 0.8 | 0.8 | +6% | 2.7 | 2.6 | time ~noise |
| io-group t=64 | 0.340 | 0.457 | +34% | 1.5 | 1.9 | +26% | 2.7 | 2.7 | time WORSE, CPU WORSE |
| io-group t=256 | 0.392 | 0.395 | +1% | 2.1 | 2.0 | -5% | 2.7 | 2.8 |  |
| io-group t=1024 | 0.473 | 0.487 | +3% | 3.4 | 3.7 | +9% | 2.9 | 2.9 |  |
| io-group t=10000 | 1.974 | 2.032 | +3% | 19.9 | 19.8 | -0% | 2.8 | 2.8 |  |
| io-group t=100000 | 17.306 | 17.596 | +2% | 181.8 | 183.4 | +1% | 2.8 | 2.8 |  |
| io-group t=1000000 | 180.398 | 180.108 | -0% | 1821.0 | 1822.4 | +0% | 2.7 | 2.7 |  |
| io-dispatch t=16 | 0.229 | 0.260 | +14% | 1.5 | 1.9 | +26% | 2.7 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch t=64 | 0.246 | 0.252 | +3% | 1.5 | 1.1 | -26% | 2.8 | 2.8 | CPU better |
| io-dispatch t=256 | 0.242 | 0.231 | -4% | 2.0 | 1.7 | -12% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch t=1024 | 0.326 | 0.313 | -4% | 2.2 | 2.1 | -7% | 2.8 | 2.8 |  |
| io-dispatch t=10000 | 1.346 | 1.380 | +3% | 10.4 | 11.0 | +6% | 2.8 | 2.8 |  |
| io-dispatch t=100000 | 11.890 | 11.925 | +0% | 94.9 | 95.6 | +1% | 2.7 | 2.8 |  |
| io-dispatch t=1000000 | 110.455 | 110.748 | +0% | 956.7 | 971.6 | +2% | 2.8 | 2.8 |  |
| io-dispatch-big t=16 | 0.272 | 0.271 | -1% | 1.1 | 1.4 | +18% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=64 | 0.246 | 0.267 | +8% | 1.4 | 1.3 | -5% | 2.8 | 2.8 |  |
| io-dispatch-big t=256 | 0.272 | 0.302 | +11% | 1.6 | 1.7 | +2% | 2.8 | 2.8 | time ~noise |
| io-dispatch-big t=1024 | 0.443 | 0.444 | +0% | 2.3 | 1.9 | -16% | 2.8 | 2.8 | CPU better |
| io-dispatch-big t=10000 | 1.574 | 1.662 | +6% | 9.3 | 10.2 | +10% | 2.8 | 2.8 |  |
| io-dispatch-big t=100000 | 12.473 | 12.640 | +1% | 99.3 | 98.3 | -1% | 2.8 | 2.8 |  |
| io-dispatch-big t=1000000 | 124.355 | 126.062 | +1% | 991.9 | 993.3 | +0% | 2.8 | 2.8 |  |

## Regressions vs main (WORSE)

- io-group t=64: time WORSE, CPU WORSE
