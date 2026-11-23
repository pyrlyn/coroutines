# Benchmark: io-spawn-blocks vs main (darwin-arm64)

- Date: 2026-11-01T16:59Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 7.6 / 16.0 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.351 | 14.327 | -0% | 14.3 | 14.3 | -0% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 798.432 | 995.301 | +25% | 824.5 | 902.6 | +9% | 2.0 | 2.0 | 1/1 | time ~noise, CPU ~noise |
| sequential | 17.461 | 17.600 | +1% | 17.2 | 17.5 | +2% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.785 | 15.926 | +1% | 15.7 | 15.8 | +1% | 2.1 | 2.1 | 1/1 |  |
| procs2 | 13.329 | 13.282 | -0% | 0.5 | 0.6 | +15% | 2.2 | 2.2 | 0/0 |  |
| sm-parallel t=16 | 0.196 | 0.188 | -4% | 0.5 | 0.5 | +5% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=64 | 0.183 | 0.192 | +5% | 0.6 | 0.5 | -7% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=255 | 0.771 | 0.662 | -14% | 1.2 | 1.1 | -7% | 2.3 | 2.3 | 1/1 | time ~noise |
| sm-parallel t=256 | 0.547 | 0.529 | -3% | 1.0 | 1.0 | -5% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=257 | 0.503 | 0.522 | +4% | 0.9 | 0.9 | -2% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=1024 | 0.557 | 0.547 | -2% | 2.1 | 2.3 | +7% | 2.4 | 2.4 | 1/1 |  |
| sm-parallel t=10000 | 1.820 | 1.819 | -0% | 18.3 | 18.4 | +0% | 2.7 | 2.7 | 1/1 |  |
| io-group t=16 | 0.210 | 0.241 | +15% | 1.0 | 1.1 | +11% | 2.5 | 2.6 | 16/16 | time WORSE |
| io-group t=64 | 0.472 | 0.483 | +2% | 1.8 | 1.9 | +5% | 2.7 | 2.6 | 64/64 |  |
| io-group t=255 | 1.154 | 0.450 | -61% | 4.1 | 2.4 | -41% | 2.7 | 2.7 | 255/64 | time better, CPU better |
| io-group t=256 | 1.243 | 0.621 | -50% | 3.9 | 1.7 | -55% | 2.8 | 3.0 | 256/64 | time better, CPU better, RSS ~noise |
| io-group t=257 | 1.091 | 0.563 | -48% | 3.5 | 1.7 | -51% | 2.8 | 2.8 | 257/64 | time better, CPU better |
| io-group t=1024 | 3.939 | 0.643 | -84% | 13.1 | 3.6 | -72% | 3.0 | 2.9 | 1024/64 | time better, CPU better |
| io-group t=10000 | 45.268 | 2.152 | -95% | 150.2 | 20.1 | -87% | 2.8 | 2.8 | 10000/64 | time better, CPU better |

## Regressions (WORSE)

- io-group t=16: time WORSE
