# Benchmark: step 4: main after #12 (6a056e9) vs 731af2d (darwin-arm64)

- Date: 2026-11-01T18:11Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 18.7 / 16.0 (the Mac was in use; small differences are noise)
- Method: one bench program (repo bench/main.zig plus sm-skew, sm-big, io-dispatch, io-dispatch-big) built against the previous main's `src/` (base) and the new main's `src/` (new). Each row: 7 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 10% and the interquartile ranges do not overlap; ~noise = >= 10% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.124 | 14.216 | +1% | 14.1 | 14.2 | +1% | 2.0 | 1.9 | 0/0 |  |
| io-switch | 702.632 | 674.776 | -4% | 712.0 | 688.9 | -3% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.761 | 16.696 | -0% | 16.7 | 16.7 | -1% | 2.0 | 1.9 | 0/0 |  |
| sm-1thread | 15.577 | 15.432 | -1% | 15.6 | 15.4 | -1% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=16 | 0.029 | 0.028 | -3% | 0.0 | 0.0 | -11% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=64 | 0.103 | 0.106 | +3% | 0.1 | 0.1 | +4% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=256 | 0.400 | 0.398 | -1% | 0.4 | 0.4 | +0% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=1024 | 0.468 | 0.452 | -3% | 1.7 | 1.7 | -2% | 2.1 | 2.1 | 1/1 |  |
| sm-parallel t=10000 | 1.585 | 1.722 | +9% | 19.2 | 18.8 | -2% | 2.8 | 2.8 | 1/1 |  |
| sm-parallel t=100000 | 13.617 | 13.783 | +1% | 180.9 | 182.8 | +1% | 4.8 | 4.8 | 1/1 |  |
| sm-parallel t=1000000 | 134.527 | 135.540 | +1% | 1780.0 | 1765.1 | -1% | 25.5 | 25.4 | 1/1 |  |
| sm-skew t=16 | 0.136 | 0.139 | +2% | 0.1 | 0.1 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=64 | 0.210 | 0.241 | +15% | 0.2 | 0.2 | +15% | 2.0 | 2.0 | 1/1 | time WORSE |
| sm-skew t=256 | 0.697 | 0.706 | +1% | 0.7 | 0.7 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=1024 | 0.768 | 0.770 | +0% | 2.8 | 2.8 | +1% | 2.1 | 2.1 | 1/1 |  |
| sm-skew t=10000 | 2.451 | 2.604 | +6% | 29.8 | 29.7 | -0% | 2.8 | 2.8 | 1/1 |  |
| sm-skew t=100000 | 21.416 | 21.382 | -0% | 285.1 | 283.9 | -0% | 4.8 | 4.8 | 1/1 |  |
| sm-skew t=1000000 | 213.261 | 212.543 | -0% | 2832.6 | 2819.7 | -0% | 25.4 | 25.4 | 1/1 |  |
| sm-big t=16 | 0.031 | 0.032 | +3% | 0.0 | 0.0 | +5% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=64 | 0.129 | 0.116 | -11% | 0.1 | 0.1 | -10% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=256 | 0.475 | 0.466 | -2% | 0.5 | 0.5 | -0% | 2.1 | 2.1 | 1/1 |  |
| sm-big t=1024 | 0.552 | 0.563 | +2% | 2.0 | 2.0 | +2% | 2.6 | 2.6 | 1/1 |  |
| sm-big t=10000 | 2.265 | 2.263 | -0% | 20.9 | 20.9 | -0% | 7.4 | 7.3 | 1/1 |  |
| sm-big t=100000 | 18.971 | 19.029 | +0% | 205.2 | 202.7 | -1% | 50.6 | 50.6 | 1/1 |  |
| sm-big t=1000000 | 179.982 | 178.428 | -1% | 2068.6 | 2045.0 | -1% | 483.2 | 483.2 | 1/1 |  |
| io-group t=16 | 0.179 | 0.195 | +9% | 1.0 | 0.8 | -13% | 2.7 | 2.6 | 16/16 |  |
| io-group t=64 | 0.379 | 0.359 | -5% | 1.6 | 1.7 | +8% | 2.7 | 2.7 | 64/64 |  |
| io-group t=256 | 0.443 | 0.408 | -8% | 2.1 | 2.1 | -2% | 2.7 | 2.7 | 64/64 |  |
| io-group t=1024 | 0.522 | 0.548 | +5% | 3.5 | 3.7 | +4% | 3.0 | 2.9 | 64/64 |  |
| io-group t=10000 | 2.077 | 2.110 | +2% | 19.7 | 19.9 | +1% | 2.8 | 2.9 | 64/64 |  |
| io-group t=100000 | 17.903 | 17.249 | -4% | 181.5 | 181.4 | -0% | 2.8 | 2.8 | 64/64 |  |
| io-group t=1000000 | 172.608 | 174.773 | +1% | 1791.1 | 1793.6 | +0% | 2.7 | 2.7 | 64/64 |  |
| io-dispatch t=16 | 0.269 | 0.263 | -2% | 2.2 | 1.6 | -26% | 2.8 | 2.8 | 16/16 | CPU ~noise |
| io-dispatch t=64 | 0.478 | 0.263 | -45% | 2.6 | 1.3 | -52% | 2.8 | 2.8 | 16/16 | time ~noise, CPU better |
| io-dispatch t=256 | 0.434 | 0.227 | -48% | 3.1 | 1.5 | -52% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch t=1024 | 3.246 | 0.321 | -90% | 18.5 | 2.1 | -89% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch t=10000 | 32.526 | 1.321 | -96% | 185.7 | 11.4 | -94% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch t=100000 | 328.572 | 11.334 | -97% | 1867.8 | 97.6 | -95% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch t=1000000 | 3102.886 | 111.211 | -96% | 17746.0 | 966.2 | -95% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=16 | 0.292 | 0.268 | -8% | 1.7 | 1.9 | +12% | 2.8 | 2.8 | 16/16 | CPU ~noise |
| io-dispatch-big t=64 | 0.625 | 0.266 | -57% | 2.8 | 1.8 | -37% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=256 | 1.327 | 0.260 | -80% | 7.0 | 1.5 | -78% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=1024 | 4.763 | 0.376 | -92% | 25.7 | 1.9 | -93% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=10000 | 43.578 | 1.507 | -97% | 240.4 | 11.2 | -95% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=100000 | 446.500 | 12.304 | -97% | 2462.4 | 101.9 | -96% | 2.8 | 2.8 | 16/16 | time better, CPU better |
| io-dispatch-big t=1000000 | 4245.331 | 121.296 | -97% | 23594.8 | 990.0 | -96% | 2.8 | 2.8 | 16/16 | time better, CPU better |

## Regressions (WORSE)

- sm-skew t=64: time WORSE

## Re-check of flagged rows (21 interleaved pairs)

- sm-skew t=64 time: 227 → 230 µs median, IQR overlap. Noise; #12 changes only `src/io.zig`.
