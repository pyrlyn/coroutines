# Benchmark: step 1: main after #7 (4ce4c64) vs 8b175b2 (darwin-arm64)

- Date: 2026-11-01T17:17Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 6.2 / 11.1 (the Mac was in use; small differences are noise)
- Method: one bench program (repo bench/main.zig plus sm-skew, sm-big, io-dispatch, io-dispatch-big) built against the previous main's `src/` (base) and the new main's `src/` (new). Each row: 7 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 10% and the interquartile ranges do not overlap; ~noise = >= 10% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.439 | 14.528 | +1% | 14.4 | 14.5 | +1% | 2.0 | 1.9 | 0/0 |  |
| io-switch | 643.177 | 691.065 | +7% | 659.4 | 708.7 | +7% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.657 | 16.671 | +0% | 16.7 | 16.7 | +0% | 2.0 | 1.9 | 0/0 |  |
| sm-1thread | 15.272 | 15.519 | +2% | 15.3 | 15.5 | +2% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=16 | 0.151 | 0.031 | -80% | 0.4 | 0.0 | -91% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=64 | 0.170 | 0.101 | -41% | 0.5 | 0.1 | -77% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=256 | 0.451 | 0.399 | -12% | 0.8 | 0.4 | -47% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=1024 | 0.496 | 0.472 | -5% | 2.1 | 1.7 | -16% | 2.4 | 2.1 | 1/1 | CPU better, RSS better |
| sm-parallel t=10000 | 1.500 | 1.510 | +1% | 18.9 | 18.8 | -1% | 2.8 | 2.7 | 1/1 |  |
| sm-parallel t=100000 | 12.881 | 12.590 | -2% | 182.4 | 182.0 | -0% | 4.8 | 4.8 | 1/1 |  |
| sm-parallel t=1000000 | 122.202 | 123.028 | +1% | 1796.5 | 1789.1 | -0% | 25.4 | 25.4 | 1/1 |  |
| sm-skew t=16 | 0.214 | 0.142 | -34% | 0.5 | 0.1 | -73% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-skew t=64 | 0.280 | 0.220 | -21% | 0.6 | 0.2 | -62% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-skew t=256 | 0.792 | 0.718 | -9% | 1.1 | 0.7 | -34% | 2.3 | 2.0 | 1/1 | CPU better, RSS better |
| sm-skew t=1024 | 0.790 | 0.747 | -5% | 3.1 | 2.8 | -10% | 2.4 | 2.1 | 1/1 | CPU better, RSS better |
| sm-skew t=10000 | 2.369 | 2.576 | +9% | 28.7 | 29.3 | +2% | 2.8 | 2.7 | 1/1 |  |
| sm-skew t=100000 | 20.406 | 20.185 | -1% | 281.1 | 283.2 | +1% | 4.8 | 4.8 | 1/1 |  |
| sm-skew t=1000000 | 190.797 | 191.198 | +0% | 2820.2 | 2813.7 | -0% | 25.4 | 25.4 | 1/1 |  |
| sm-big t=16 | 0.149 | 0.034 | -77% | 0.4 | 0.0 | -89% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-big t=64 | 0.192 | 0.131 | -32% | 0.5 | 0.1 | -72% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-big t=256 | 0.591 | 0.525 | -11% | 0.9 | 0.5 | -38% | 2.4 | 2.1 | 1/1 | time better, CPU better, RSS better |
| sm-big t=1024 | 0.638 | 0.588 | -8% | 2.6 | 2.1 | -16% | 2.9 | 2.6 | 1/1 | CPU better, RSS better |
| sm-big t=10000 | 2.160 | 2.257 | +4% | 23.0 | 23.0 | +0% | 7.4 | 7.3 | 1/1 |  |
| sm-big t=100000 | 18.551 | 18.513 | -0% | 229.5 | 230.2 | +0% | 50.6 | 50.6 | 1/1 |  |
| sm-big t=1000000 | 180.631 | 177.981 | -1% | 2266.5 | 2275.4 | +0% | 483.2 | 483.2 | 1/1 |  |
| io-group t=16 | 0.184 | 0.188 | +2% | 0.8 | 1.2 | +47% | 2.7 | 2.6 | 16/16 | CPU ~noise |
| io-group t=64 | 0.356 | 0.387 | +9% | 1.6 | 1.6 | -4% | 2.8 | 2.6 | 64/64 |  |
| io-group t=256 | 0.878 | 0.861 | -2% | 3.4 | 3.2 | -6% | 2.7 | 2.7 | 256/256 |  |
| io-group t=1024 | 3.124 | 3.202 | +2% | 11.0 | 11.4 | +4% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 27.754 | 28.145 | +1% | 96.5 | 98.2 | +2% | 2.8 | 2.7 | 10000/10000 |  |
| io-group t=100000 | 296.251 | 297.878 | +1% | 998.3 | 1005.6 | +1% | 2.8 | 2.8 | 100000/100000 |  |
| io-group t=1000000 | 3016.202 | 3036.169 | +1% | 10106.4 | 10194.2 | +1% | 3.2 | 3.3 | 1000000/1000000 |  |
| io-dispatch t=16 | 0.285 | 0.229 | -20% | 1.6 | 1.5 | -9% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch t=64 | 0.260 | 0.364 | +40% | 2.4 | 2.5 | +4% | 2.8 | 2.7 | 16/16 | time ~noise |
| io-dispatch t=256 | 1.028 | 0.657 | -36% | 5.8 | 3.7 | -36% | 2.8 | 2.7 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 3.005 | 3.570 | +19% | 18.4 | 21.0 | +14% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 27.455 | 26.883 | -2% | 166.5 | 161.9 | -3% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch t=100000 | 297.862 | 287.661 | -3% | 1764.2 | 1689.8 | -4% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch t=1000000 | 3040.115 | 2952.903 | -3% | 17785.0 | 17372.4 | -2% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=16 | 0.294 | 0.292 | -1% | 1.6 | 1.4 | -17% | 2.8 | 2.8 | 16/16 | CPU ~noise |
| io-dispatch-big t=64 | 0.389 | 0.307 | -21% | 2.4 | 1.8 | -26% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch-big t=256 | 0.796 | 1.065 | +34% | 4.5 | 5.8 | +28% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch-big t=1024 | 4.825 | 4.079 | -15% | 25.6 | 23.2 | -9% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch-big t=10000 | 43.613 | 43.368 | -1% | 243.2 | 243.6 | +0% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=100000 | 435.948 | 437.183 | +0% | 2391.1 | 2407.6 | +1% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=1000000 | 4403.082 | 4476.079 | +2% | 24354.6 | 24711.9 | +1% | 2.8 | 2.8 | 16/16 |  |

## Regressions (WORSE)

- none
