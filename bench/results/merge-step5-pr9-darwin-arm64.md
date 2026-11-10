# Benchmark: step 5: main after #9 (65b74e7) vs 6a056e9 (darwin-arm64)

- Date: 2026-11-01T18:18Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 5.4 / 9.9 (the Mac was in use; small differences are noise)
- Method: one bench program (repo bench/main.zig plus sm-skew, sm-big, io-dispatch, io-dispatch-big) built against the previous main's `src/` (base) and the new main's `src/` (new). Each row: 7 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 10% and the interquartile ranges do not overlap; ~noise = >= 10% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.090 | 14.082 | -0% | 14.1 | 14.1 | -0% | 1.9 | 2.0 | 0/0 |  |
| io-switch | 723.336 | 735.786 | +2% | 723.4 | 734.5 | +2% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.735 | 16.731 | -0% | 16.7 | 16.7 | -0% | 2.0 | 2.0 | 0/0 |  |
| sm-1thread | 15.398 | 15.394 | -0% | 15.4 | 15.4 | -0% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=16 | 0.029 | 0.033 | +16% | 0.0 | 0.0 | +16% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=64 | 0.103 | 0.102 | -1% | 0.1 | 0.1 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=256 | 0.416 | 0.446 | +7% | 0.4 | 0.4 | +7% | 2.0 | 2.0 | 1/1 |  |
| sm-parallel t=1024 | 0.490 | 0.478 | -2% | 1.8 | 1.8 | +1% | 2.1 | 2.2 | 1/1 |  |
| sm-parallel t=10000 | 1.791 | 1.685 | -6% | 18.7 | 19.7 | +5% | 2.8 | 2.9 | 1/1 |  |
| sm-parallel t=100000 | 14.284 | 14.623 | +2% | 177.6 | 178.3 | +0% | 4.8 | 4.9 | 1/1 |  |
| sm-parallel t=1000000 | 136.198 | 134.534 | -1% | 1768.0 | 1764.4 | -0% | 25.4 | 25.5 | 1/1 |  |
| sm-skew t=16 | 0.136 | 0.142 | +5% | 0.1 | 0.1 | +4% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=64 | 0.220 | 0.225 | +2% | 0.2 | 0.2 | +1% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=256 | 0.700 | 0.712 | +2% | 0.7 | 0.7 | +3% | 2.0 | 2.0 | 1/1 |  |
| sm-skew t=1024 | 0.782 | 0.813 | +4% | 2.9 | 2.9 | +1% | 2.1 | 2.1 | 1/1 |  |
| sm-skew t=10000 | 2.704 | 2.753 | +2% | 29.6 | 30.5 | +3% | 2.8 | 2.8 | 1/1 |  |
| sm-skew t=100000 | 21.805 | 22.019 | +1% | 279.7 | 281.8 | +1% | 4.8 | 4.9 | 1/1 |  |
| sm-skew t=1000000 | 218.789 | 217.132 | -1% | 2763.7 | 2783.0 | +1% | 25.4 | 25.5 | 1/1 |  |
| sm-big t=16 | 0.031 | 0.031 | +1% | 0.0 | 0.0 | -3% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=64 | 0.115 | 0.118 | +3% | 0.1 | 0.1 | +2% | 2.0 | 2.0 | 1/1 |  |
| sm-big t=256 | 0.474 | 0.480 | +1% | 0.5 | 0.5 | +2% | 2.1 | 2.1 | 1/1 |  |
| sm-big t=1024 | 0.551 | 0.551 | +0% | 2.0 | 2.0 | -0% | 2.6 | 2.6 | 1/1 |  |
| sm-big t=10000 | 2.287 | 2.188 | -4% | 20.5 | 21.1 | +3% | 7.3 | 7.4 | 1/1 |  |
| sm-big t=100000 | 18.929 | 19.087 | +1% | 203.3 | 206.6 | +2% | 50.6 | 50.7 | 1/1 |  |
| sm-big t=1000000 | 189.013 | 196.384 | +4% | 2029.3 | 2030.3 | +0% | 483.2 | 483.3 | 1/1 |  |
| io-group t=16 | 0.217 | 0.189 | -13% | 1.1 | 0.8 | -26% | 2.7 | 2.6 | 16/16 | time better, CPU better |
| io-group t=64 | 0.367 | 0.461 | +26% | 1.6 | 1.9 | +19% | 2.7 | 2.7 | 64/64 | time WORSE, CPU ~noise |
| io-group t=256 | 0.385 | 0.396 | +3% | 2.1 | 2.0 | -3% | 2.8 | 2.7 | 64/64 |  |
| io-group t=1024 | 0.508 | 0.475 | -6% | 3.4 | 3.4 | +0% | 2.9 | 3.0 | 64/64 |  |
| io-group t=10000 | 2.151 | 2.212 | +3% | 19.7 | 20.1 | +2% | 2.9 | 2.8 | 64/64 |  |
| io-group t=100000 | 19.308 | 19.449 | +1% | 182.1 | 182.0 | -0% | 2.8 | 2.8 | 64/64 |  |
| io-group t=1000000 | 186.076 | 185.758 | -0% | 1811.4 | 1802.3 | -1% | 2.7 | 2.8 | 64/64 |  |
| io-dispatch t=16 | 0.230 | 0.276 | +20% | 1.7 | 1.9 | +13% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=64 | 0.243 | 0.282 | +16% | 1.4 | 2.0 | +50% | 2.8 | 2.8 | 16/16 | time ~noise, CPU WORSE |
| io-dispatch t=256 | 0.242 | 0.273 | +13% | 1.7 | 1.5 | -14% | 2.8 | 2.8 | 16/16 | time ~noise, CPU ~noise |
| io-dispatch t=1024 | 0.332 | 0.384 | +16% | 2.0 | 2.0 | -1% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch t=10000 | 1.446 | 1.403 | -3% | 10.4 | 9.9 | -6% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch t=100000 | 12.204 | 12.448 | +2% | 94.3 | 96.3 | +2% | 2.7 | 2.8 | 16/16 |  |
| io-dispatch t=1000000 | 118.108 | 118.841 | +1% | 944.4 | 930.0 | -2% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=16 | 0.228 | 0.252 | +10% | 1.4 | 1.3 | -1% | 2.8 | 2.8 | 16/16 | time ~noise |
| io-dispatch-big t=64 | 0.230 | 0.261 | +13% | 1.2 | 1.4 | +20% | 2.8 | 2.8 | 16/16 | time WORSE, CPU ~noise |
| io-dispatch-big t=256 | 0.276 | 0.267 | -3% | 1.5 | 1.4 | -8% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=1024 | 0.379 | 0.344 | -9% | 2.0 | 2.0 | -2% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=10000 | 1.585 | 1.529 | -4% | 11.6 | 11.5 | -1% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=100000 | 12.502 | 12.838 | +3% | 98.1 | 97.1 | -1% | 2.8 | 2.8 | 16/16 |  |
| io-dispatch-big t=1000000 | 131.474 | 130.960 | -0% | 939.6 | 946.1 | +1% | 2.8 | 2.8 | 16/16 |  |

## Regressions (WORSE)

- io-group t=64: time WORSE
- io-dispatch t=64: CPU WORSE
- io-dispatch-big t=64: time WORSE

## Re-check of flagged rows (21 interleaved pairs each)

- io-group t=64 time: 392 → 400 µs (IQR 356–471 vs 341–450). io-dispatch t=64 CPU: 1272 → 1372 µs (IQR overlap). io-dispatch-big t=64 time: 260 → 242 µs. All noise; #9 changes only `src/state_machine.zig`.
- sm-parallel t=16 time (+16% above, unflagged): 28 → 29 µs. Noise.

Note: on top of #7 (workers capped at the chunk count) #9 no longer shows the gains measured on its branch against 8b175b2 (sm-parallel t=255..257 −51..60%, sm-skew t=1024 −47%): with t ≤ chunk only one worker runs, so the tapered chunks have nobody to balance across. No regressions either.
