# Benchmark: dispatcher-batch vs main (darwin-arm64)

- Date: 2026-11-01T17:00Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 15.2 / 11.7 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.577 | 14.699 | +1% | 14.6 | 14.7 | +1% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 719.462 | 715.591 | -1% | 745.9 | 739.2 | -1% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.711 | 16.724 | +0% | 16.7 | 16.7 | +0% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.362 | 15.356 | -0% | 15.4 | 15.4 | -0% | 2.1 | 2.1 | 1/1 |  |
| procs2 | 11.586 | 11.319 | -2% | 0.4 | 0.4 | -3% | 2.1 | 2.1 | 0/0 |  |
| sm-parallel t=16 | 0.146 | 0.156 | +7% | 0.3 | 0.4 | +5% | 2.2 | 2.2 | 1/1 |  |
| sm-parallel t=64 | 0.165 | 0.167 | +1% | 0.4 | 0.4 | +2% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=255 | 0.465 | 0.476 | +2% | 0.8 | 0.7 | -0% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=256 | 0.483 | 0.471 | -2% | 0.8 | 0.7 | -9% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=257 | 0.461 | 0.482 | +5% | 0.7 | 0.8 | +4% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=1024 | 0.510 | 0.498 | -2% | 2.4 | 2.3 | -4% | 2.4 | 2.4 | 1/1 |  |
| sm-parallel t=10000 | 1.513 | 1.509 | -0% | 18.7 | 18.8 | +0% | 2.7 | 2.7 | 1/1 |  |
| io-group t=16 | 0.185 | 0.195 | +6% | 0.8 | 0.9 | +11% | 2.6 | 2.6 | 16/16 |  |
| io-group t=64 | 0.365 | 0.386 | +6% | 1.5 | 1.5 | +0% | 2.7 | 2.7 | 64/64 | time ~noise |
| io-group t=255 | 1.019 | 0.972 | -5% | 3.7 | 3.5 | -5% | 2.6 | 2.7 | 255/255 |  |
| io-group t=256 | 1.163 | 1.062 | -9% | 4.0 | 3.7 | -8% | 2.7 | 2.7 | 256/256 | time ~noise, CPU ~noise |
| io-group t=257 | 0.971 | 1.044 | +8% | 3.4 | 3.7 | +8% | 2.8 | 2.7 | 257/257 | time ~noise, CPU ~noise |
| io-group t=1024 | 3.540 | 3.582 | +1% | 12.2 | 12.7 | +4% | 2.8 | 2.8 | 1024/1024 |  |
| io-group t=10000 | 32.468 | 32.541 | +0% | 107.5 | 108.0 | +0% | 2.8 | 2.7 | 10000/10000 |  |
| io-dispatch t=1000 | 33.231 | 1.319 | -96% | 184.2 | 10.5 | -94% | 2.7 | 2.7 | 16/16 | time better, CPU better |
| io-dispatch t=10000 | 331.152 | 10.834 | -97% | 1873.6 | 98.6 | -95% | 2.8 | 2.7 | 16/16 | time better, CPU better |

## Regressions (WORSE)

- none
