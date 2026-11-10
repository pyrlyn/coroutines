# Benchmark: step 3: main after #11 (731af2d) vs 83a4cbe (darwin-arm64)

- Date: 2026-11-01T18:03Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 112.4 / 19.5 (the Mac was in use; small differences are noise)
- Method: one bench program (repo bench/main.zig plus sm-skew, sm-big, io-dispatch, io-dispatch-big) built against the previous main's `src/` (base) and the new main's `src/` (new). Each row: 7 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 10% and the interquartile ranges do not overlap; ~noise = >= 10% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.077 | 14.070 | -0% | 14.0 | 14.0 | -0% | 1.9 | 2.0 | 0/0 |  |
| io-switch | 780.734 | 779.510 | -0% | 809.5 | 807.1 | -0% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.796 | 16.333 | -3% | 16.7 | 16.3 | -2% | 1.9 | 2.0 | 0/0 |  |
| sm-1thread | 15.576 | 15.334 | -2% | 15.6 | 15.3 | -2% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=16 | 0.029 | 0.029 | -1% | 0.0 | 0.0 | -3% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=64 | 0.105 | 0.102 | -3% | 0.1 | 0.1 | -4% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=256 | 0.417 | 0.412 | -1% | 0.4 | 0.4 | -0% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=1024 | 0.485 | 0.482 | -1% | 1.8 | 1.8 | +0% | 2.1 | 2.1 | 1/1 |  |
| sm-parallel t=10000 | 1.826 | 1.851 | +1% | 18.3 | 18.6 | +2% | 2.8 | 2.8 | 1/1 |  |
| sm-parallel t=100000 | 16.840 | 17.599 | +5% | 177.2 | 172.6 | -3% | 4.8 | 4.9 | 1/1 |  |
| sm-parallel t=1000000 | 138.243 | 136.064 | -2% | 1775.2 | 1766.4 | -0% | 25.4 | 25.4 | 1/1 |  |
| sm-skew t=16 | 0.134 | 0.134 | -0% | 0.1 | 0.1 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=64 | 0.209 | 0.208 | -1% | 0.2 | 0.2 | +0% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=256 | 0.688 | 0.701 | +2% | 0.7 | 0.7 | +2% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=1024 | 0.757 | 0.762 | +1% | 2.8 | 2.8 | +0% | 2.1 | 2.1 | 1/1 |  |
| sm-skew t=10000 | 2.710 | 2.450 | -10% | 29.2 | 29.3 | +0% | 2.8 | 2.8 | 1/1 |  |
| sm-skew t=100000 | 25.542 | 26.288 | +3% | 284.3 | 284.2 | -0% | 4.8 | 4.8 | 1/1 |  |
| sm-skew t=1000000 | 209.015 | 205.644 | -2% | 2805.0 | 2808.6 | +0% | 25.4 | 25.4 | 1/1 |  |
| sm-big t=16 | 0.031 | 0.031 | -0% | 0.0 | 0.0 | -3% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=64 | 0.114 | 0.114 | +0% | 0.1 | 0.1 | +0% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=256 | 0.453 | 0.462 | +2% | 0.5 | 0.5 | +2% | 2.1 | 2.1 | 1/1 |  |
| sm-big t=1024 | 0.561 | 0.553 | -1% | 2.0 | 1.9 | -0% | 2.6 | 2.6 | 1/1 |  |
| sm-big t=10000 | 2.136 | 2.092 | -2% | 20.7 | 20.8 | +1% | 7.3 | 7.4 | 1/1 |  |
| sm-big t=100000 | 19.246 | 18.207 | -5% | 195.5 | 199.1 | +2% | 50.6 | 50.6 | 1/1 |  |
| sm-big t=1000000 | 174.908 | 169.935 | -3% | 2052.1 | 2055.4 | +0% | 483.2 | 483.2 | 1/1 |  |
| io-group t=16 | 0.192 | 0.218 | +14% | 0.9 | 0.9 | -1% | 2.7 | 2.7 | 16/16 | time ~noise |
| io-group t=64 | 0.323 | 0.342 | +6% | 1.3 | 1.6 | +17% | 2.8 | 2.7 | 64/64 | CPU WORSE |
| io-group t=256 | 1.003 | 0.411 | -59% | 3.9 | 2.0 | -48% | 2.7 | 2.7 | 256/64 | time better, CPU better |
| io-group t=1024 | 3.916 | 0.539 | -86% | 12.6 | 3.5 | -72% | 2.7 | 2.8 | 1024/64 | time better, CPU better |
| io-group t=10000 | 34.177 | 1.978 | -94% | 110.3 | 19.4 | -82% | 2.8 | 2.8 | 10000/64 | time better, CPU better |
| io-group t=100000 | 346.236 | 17.834 | -95% | 1152.9 | 179.3 | -84% | 2.9 | 2.8 | 100000/64 | time better, CPU better |
| io-group t=1000000 | 3168.733 | 171.888 | -95% | 10600.9 | 1804.5 | -83% | 3.7 | 2.7 | 1000000/64 | time better, CPU better, RSS better |
| io-dispatch t=16 | 0.287 | 0.258 | -10% | 1.8 | 1.7 | -5% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch t=64 | 0.266 | 0.300 | +13% | 3.2 | 2.8 | -12% | 2.7 | 2.8 | 16/16 | time WORSE, CPU ~noise |
| io-dispatch t=256 | 0.991 | 1.568 | +58% | 5.3 | 8.5 | +60% | 2.7 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 3.128 | 4.063 | +30% | 18.7 | 23.3 | +25% | 2.7 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 26.278 | 25.731 | -2% | 161.1 | 156.8 | -3% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch t=100000 | 300.427 | 308.661 | +3% | 1757.6 | 1805.6 | +3% | 2.7 | 2.8 | 16/16 |  |
| io-dispatch t=1000000 | 3266.158 | 3131.416 | -4% | 18569.8 | 17918.6 | -4% | 2.7 | 2.8 | 16/16 |  |
| io-dispatch-big t=16 | 0.304 | 0.257 | -15% | 1.7 | 2.2 | +25% | 2.8 | 2.8 | 16/16 | time better, CPU ~noise |
| io-dispatch-big t=64 | 0.421 | 0.558 | +32% | 2.6 | 3.5 | +35% | 2.8 | 2.8 | 16/16 | time WORSE, CPU ~noise |
| io-dispatch-big t=256 | 1.459 | 1.252 | -14% | 6.9 | 6.7 | -4% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch-big t=1024 | 4.781 | 4.931 | +3% | 25.8 | 26.5 | +3% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=10000 | 44.572 | 43.162 | -3% | 241.2 | 244.4 | +1% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=100000 | 411.606 | 419.017 | +2% | 2303.8 | 2339.8 | +2% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=1000000 | 4275.738 | 4383.487 | +3% | 23617.7 | 24283.9 | +3% | 2.8 | 2.8 | 16/16 |  |

## Regressions (WORSE)

- io-group t=64: CPU WORSE
- io-dispatch t=64: time WORSE
- io-dispatch-big t=64: time WORSE

## Re-check of flagged rows (21 interleaved pairs each)

- io-group t=64 CPU: 1548 → 1792 µs median, IQR 1290–1752 vs 1512–1994 (overlap). Noise.
- io-dispatch t=64 time: 321 → 294 µs. io-dispatch-big t=64 time: 430 → 303 µs. Noise; #11 does not touch `Dispatcher`.
