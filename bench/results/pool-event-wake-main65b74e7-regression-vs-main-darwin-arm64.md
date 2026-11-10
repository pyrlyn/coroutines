# Benchmark: pool-event-wake on main 65b74e7 (regression suite) vs main (darwin-arm64)

runParallel, Io group, Dispatcher small (8 B) and large (256 B) messages; code identical to main except Pool. 7 interleaved runs.

- Date: 2026-11-01
- Machine: Ivan's Mac, Apple M3 Max, 16 logical CPUs; Zig 0.17.0, ReleaseFast
- Load average (1 min) during the run: min 47.7, median 57.3, max 80.4. The Mac was busy with other work; treat < 10-15% differences as noise.
- Method: one bench binary per variant (same bench/main.zig, library `src/` swapped). 7 runs per variant per row, all variants interleaved in random order, each a fresh process. Medians shown. main has no `Pool`, so its sm-repeat rows call `runParallel` per round. WORSE / better = median differs by >= 10% and IQRs do not overlap; ~noise = >= 10% but IQRs overlap. CPU = user+sys of the whole variant incl. setup. RSS = peak resident set.
- Rows: sm-repeat = back-to-back runs of N small even tasks (500 rounds for N <= 1024, fewer for larger N); -skew = every 97th task 64x longer; -big = 504-byte tasks with uneven lengths; -long = 16x longer tasks; -gap = 100 us idle between rounds (mostly idle app).

| scenario | main ms | new ms | time Δ | main CPU ms | new CPU ms | CPU Δ | main RSS MB | new RSS MB | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.543 | 14.440 | -1% | 14.4 | 14.3 | -0% | 2.0 | 1.9 |  |
| io-switch | 739.973 | 735.280 | -1% | 754.9 | 750.9 | -1% | 2.0 | 2.0 |  |
| sequential | 17.264 | 17.098 | -1% | 17.0 | 17.0 | -0% | 2.0 | 1.9 |  |
| sm-1thread | 15.636 | 15.653 | +0% | 15.6 | 15.6 | +0% | 2.2 | 2.2 |  |
| sm-parallel t=16 | 0.031 | 0.030 | -5% | 0.0 | 0.0 | -3% | 2.0 | 2.0 |  |
| sm-parallel t=64 | 0.105 | 0.112 | +7% | 0.1 | 0.1 | +8% | 2.0 | 2.0 |  |
| sm-parallel t=256 | 0.442 | 0.425 | -4% | 0.4 | 0.4 | -3% | 2.0 | 2.0 |  |
| sm-parallel t=1024 | 0.470 | 0.459 | -2% | 1.8 | 1.7 | -2% | 2.1 | 2.2 |  |
| sm-parallel t=10000 | 1.626 | 1.599 | -2% | 19.9 | 20.2 | +2% | 2.9 | 2.9 |  |
| sm-parallel t=100000 | 13.788 | 13.726 | -0% | 182.8 | 182.0 | -0% | 4.9 | 5.0 |  |
| sm-parallel t=1000000 | 134.064 | 135.518 | +1% | 1773.3 | 1772.4 | -0% | 25.5 | 25.6 |  |
| sm-skew t=16 | 0.141 | 0.143 | +1% | 0.1 | 0.2 | +4% | 2.0 | 2.0 |  |
| sm-skew t=64 | 0.211 | 0.217 | +3% | 0.2 | 0.2 | +3% | 2.0 | 2.0 |  |
| sm-skew t=256 | 0.705 | 0.737 | +5% | 0.7 | 0.7 | +5% | 2.0 | 2.0 |  |
| sm-skew t=1024 | 0.809 | 0.845 | +4% | 3.0 | 3.0 | +2% | 2.1 | 2.2 |  |
| sm-skew t=10000 | 2.768 | 2.832 | +2% | 30.1 | 29.7 | -2% | 2.8 | 2.8 |  |
| sm-skew t=100000 | 21.499 | 21.652 | +1% | 284.6 | 283.8 | -0% | 4.9 | 4.9 |  |
| sm-skew t=1000000 | 213.001 | 212.970 | -0% | 2801.6 | 2806.4 | +0% | 25.5 | 25.5 |  |
| sm-big t=16 | 0.031 | 0.031 | +1% | 0.0 | 0.0 | +8% | 2.0 | 2.0 |  |
| sm-big t=64 | 0.112 | 0.115 | +2% | 0.1 | 0.1 | +3% | 2.0 | 2.0 |  |
| sm-big t=256 | 0.447 | 0.449 | +1% | 0.5 | 0.5 | +2% | 2.1 | 2.1 |  |
| sm-big t=1024 | 0.545 | 0.559 | +3% | 2.0 | 2.0 | +0% | 2.6 | 2.6 |  |
| sm-big t=10000 | 2.073 | 2.075 | +0% | 21.7 | 21.9 | +1% | 7.4 | 7.4 |  |
| sm-big t=100000 | 18.354 | 18.147 | -1% | 206.6 | 205.6 | -0% | 50.7 | 50.7 |  |
| sm-big t=1000000 | 179.323 | 181.742 | +1% | 2048.8 | 2040.0 | -0% | 483.3 | 483.3 |  |
| io-group t=16 | 0.207 | 0.209 | +1% | 0.8 | 0.8 | +2% | 2.7 | 2.7 |  |
| io-group t=64 | 0.340 | 0.358 | +5% | 1.5 | 1.4 | -6% | 2.7 | 2.7 |  |
| io-group t=256 | 0.392 | 0.449 | +14% | 2.1 | 2.2 | +5% | 2.7 | 2.8 | time ~noise |
| io-group t=1024 | 0.473 | 0.494 | +4% | 3.4 | 3.8 | +9% | 2.9 | 2.8 |  |
| io-group t=10000 | 1.974 | 2.043 | +3% | 19.9 | 19.9 | +0% | 2.8 | 2.8 |  |
| io-group t=100000 | 17.306 | 17.757 | +3% | 181.8 | 181.8 | +0% | 2.8 | 2.8 |  |
| io-group t=1000000 | 180.398 | 184.278 | +2% | 1821.0 | 1815.7 | -0% | 2.7 | 2.7 |  |
| io-dispatch t=16 | 0.229 | 0.242 | +6% | 1.5 | 1.7 | +12% | 2.7 | 2.8 |  |
| io-dispatch t=64 | 0.246 | 0.252 | +3% | 1.5 | 1.4 | -8% | 2.8 | 2.8 |  |
| io-dispatch t=256 | 0.242 | 0.252 | +4% | 2.0 | 2.1 | +5% | 2.8 | 2.8 |  |
| io-dispatch t=1024 | 0.326 | 0.346 | +6% | 2.2 | 2.1 | -8% | 2.8 | 2.8 |  |
| io-dispatch t=10000 | 1.346 | 1.403 | +4% | 10.4 | 10.5 | +1% | 2.8 | 2.8 |  |
| io-dispatch t=100000 | 11.890 | 11.845 | -0% | 94.9 | 95.8 | +1% | 2.7 | 2.8 |  |
| io-dispatch t=1000000 | 110.455 | 112.459 | +2% | 956.7 | 965.3 | +1% | 2.8 | 2.8 |  |
| io-dispatch-big t=16 | 0.272 | 0.299 | +10% | 1.1 | 1.9 | +62% | 2.8 | 2.8 | time ~noise, CPU WORSE |
| io-dispatch-big t=64 | 0.246 | 0.293 | +19% | 1.4 | 1.9 | +33% | 2.8 | 2.8 | time ~noise, CPU ~noise |
| io-dispatch-big t=256 | 0.272 | 0.304 | +12% | 1.6 | 1.7 | +2% | 2.8 | 2.8 | time ~noise |
| io-dispatch-big t=1024 | 0.443 | 0.405 | -9% | 2.3 | 2.8 | +22% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=10000 | 1.574 | 1.690 | +7% | 9.3 | 10.7 | +15% | 2.8 | 2.8 | CPU ~noise |
| io-dispatch-big t=100000 | 12.473 | 12.571 | +1% | 99.3 | 98.3 | -1% | 2.8 | 2.8 |  |
| io-dispatch-big t=1000000 | 124.355 | 123.994 | -0% | 991.9 | 991.6 | -0% | 2.8 | 2.8 |  |

## Regressions vs main (WORSE)

- io-dispatch-big t=16: CPU WORSE
