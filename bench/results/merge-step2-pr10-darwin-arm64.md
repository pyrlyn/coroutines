# Benchmark: step 2: main after #10 (83a4cbe) vs 4ce4c64 (darwin-arm64)

- Date: 2026-11-01T17:23Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 33.7 / 28.1 (the Mac was in use; small differences are noise)
- Method: one bench program (repo bench/main.zig plus sm-skew, sm-big, io-dispatch, io-dispatch-big) built against the previous main's `src/` (base) and the new main's `src/` (new). Each row: 7 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 10% and the interquartile ranges do not overlap; ~noise = >= 10% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 19.442 | 22.132 | +14% | 16.4 | 15.5 | -6% | 2.0 | 1.9 | 0/0 | time ~noise |
| io-switch | 1244.654 | 1322.353 | +6% | 824.1 | 831.6 | +1% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.721 | 17.117 | +2% | 16.7 | 16.8 | +1% | 2.0 | 1.9 | 0/0 |  |
| sm-1thread | 19.066 | 17.417 | -9% | 16.7 | 15.4 | -7% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=16 | 0.032 | 0.029 | -10% | 0.0 | 0.0 | -5% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=64 | 0.121 | 0.110 | -9% | 0.1 | 0.1 | -10% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=256 | 0.407 | 0.405 | -1% | 0.4 | 0.4 | -0% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=1024 | 0.472 | 0.482 | +2% | 1.7 | 1.8 | +4% | 2.1 | 2.2 | 1/1 |  |
| sm-parallel t=10000 | 2.882 | 3.027 | +5% | 18.4 | 18.5 | +1% | 2.7 | 2.6 | 1/1 |  |
| sm-parallel t=100000 | 22.500 | 22.316 | -1% | 183.7 | 183.3 | -0% | 4.8 | 4.8 | 1/1 |  |
| sm-parallel t=1000000 | 128.834 | 168.728 | +31% | 1748.9 | 1734.1 | -1% | 25.4 | 25.4 | 1/1 | time ~noise |
| sm-skew t=16 | 0.147 | 0.145 | -1% | 0.1 | 0.1 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=64 | 0.221 | 0.230 | +4% | 0.2 | 0.2 | +4% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=256 | 0.760 | 0.778 | +2% | 0.8 | 0.8 | +4% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=1024 | 0.757 | 0.788 | +4% | 2.8 | 2.8 | +1% | 2.1 | 2.1 | 1/1 |  |
| sm-skew t=10000 | 2.826 | 2.737 | -3% | 29.0 | 28.4 | -2% | 2.8 | 2.8 | 1/1 |  |
| sm-skew t=100000 | 20.805 | 20.448 | -2% | 282.4 | 283.7 | +0% | 4.8 | 4.8 | 1/1 |  |
| sm-skew t=1000000 | 194.871 | 198.279 | +2% | 2813.4 | 2783.7 | -1% | 25.4 | 25.4 | 1/1 |  |
| sm-big t=16 | 0.035 | 0.030 | -14% | 0.0 | 0.0 | -12% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=64 | 0.132 | 0.117 | -11% | 0.1 | 0.1 | -11% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=256 | 0.536 | 0.503 | -6% | 0.5 | 0.5 | -7% | 2.1 | 2.1 | 1/1 |  |
| sm-big t=1024 | 0.620 | 0.558 | -10% | 2.2 | 2.0 | -9% | 2.6 | 2.6 | 1/1 | time better |
| sm-big t=10000 | 2.243 | 2.101 | -6% | 22.8 | 20.6 | -9% | 7.3 | 7.4 | 1/1 |  |
| sm-big t=100000 | 19.069 | 17.519 | -8% | 227.7 | 206.4 | -9% | 50.6 | 50.6 | 1/1 |  |
| sm-big t=1000000 | 187.436 | 169.140 | -10% | 2252.8 | 2052.7 | -9% | 483.2 | 483.2 | 1/1 |  |
| io-group t=16 | 0.193 | 0.181 | -6% | 0.9 | 0.8 | -12% | 2.6 | 2.6 | 16/16 |  |
| io-group t=64 | 0.416 | 0.407 | -2% | 1.8 | 1.8 | -1% | 2.7 | 2.7 | 64/64 |  |
| io-group t=256 | 1.578 | 1.611 | +2% | 5.3 | 5.6 | +5% | 2.7 | 2.7 | 256/256 |  |
| io-group t=1024 | 4.097 | 3.881 | -5% | 13.6 | 13.1 | -3% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 34.182 | 34.355 | +1% | 113.8 | 115.6 | +2% | 2.8 | 2.9 | 10000/10000 |  |
| io-group t=100000 | 318.319 | 311.874 | -2% | 1072.1 | 1058.2 | -1% | 2.8 | 3.0 | 100000/100000 |  |
| io-group t=1000000 | 3095.686 | 3152.534 | +2% | 10449.9 | 10658.1 | +2% | 3.4 | 4.0 | 1000000/1000000 | RSS ~noise |
| io-dispatch t=16 | 0.350 | 0.337 | -4% | 1.8 | 1.7 | -8% | 2.8 | 2.7 | 16/16 |  |
| io-dispatch t=64 | 0.323 | 0.432 | +34% | 3.0 | 3.0 | -1% | 2.8 | 2.7 | 16/16 | time ~noise |
| io-dispatch t=256 | 0.433 | 0.385 | -11% | 4.7 | 5.2 | +9% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch t=1024 | 3.537 | 2.652 | -25% | 19.6 | 14.4 | -27% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=10000 | 34.718 | 33.660 | -3% | 197.7 | 194.9 | -1% | 2.8 | 2.7 | 16/16 |  |
| io-dispatch t=100000 | 196.990 | 240.262 | +22% | 1179.9 | 1392.5 | +18% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=1000000 | 2053.863 | 1430.311 | -30% | 11942.4 | 3639.0 | -70% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch-big t=16 | 0.337 | 0.971 | +188% | 0.8 | 1.0 | +21% | 2.7 | 2.7 | 16/16 | time ~noise |
| io-dispatch-big t=64 | 1.200 | 1.718 | +43% | 0.7 | 0.9 | +18% | 2.6 | 2.6 | 16/16 | time ~noise |
| io-dispatch-big t=256 | 1.704 | 0.958 | -44% | 1.1 | 1.1 | +6% | 2.8 | 2.6 | 16/16 | time better |
| io-dispatch-big t=1024 | 1.098 | 1.078 | -2% | 4.4 | 5.0 | +14% | 2.8 | 2.8 | 16/16 | CPU ~noise |
| io-dispatch-big t=10000 | 22.174 | 20.508 | -8% | 36.3 | 35.4 | -3% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=100000 | 245.905 | 269.966 | +10% | 577.8 | 636.5 | +10% | 2.8 | 2.8 | 16/16 | CPU ~noise |
| io-dispatch-big t=1000000 | 1388.807 | 1571.302 | +13% | 3182.3 | 3339.5 | +5% | 2.8 | 2.8 | 16/16 | time ~noise |

## Regressions (WORSE)

- none

## Re-check

- sm-parallel t=1000000 (+31% above, ranges overlapping): 15 more interleaved pairs, median 172 ms → 160 ms. Noise.
