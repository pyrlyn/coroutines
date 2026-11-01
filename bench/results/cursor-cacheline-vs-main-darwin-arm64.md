# Benchmark: cursor-cacheline vs main (darwin-arm64)

- Date: 2026-11-01T16:57Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 6.2 / 11.4 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 15.375 | 18.042 | +17% | 15.4 | 16.6 | +8% | 1.9 | 1.9 | 0/0 | time ~noise, CPU ~noise |
| io-switch | 792.444 | 805.947 | +2% | 821.9 | 837.6 | +2% | 2.0 | 2.0 | 1/1 |  |
| sequential | 15.869 | 15.847 | -0% | 15.9 | 15.9 | -0% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 14.563 | 14.553 | -0% | 14.6 | 14.6 | -0% | 2.1 | 2.2 | 1/1 |  |
| procs2 | 10.844 | 10.931 | +1% | 0.3 | 0.3 | +0% | 2.1 | 2.2 | 0/0 |  |
| sm-parallel t=16 | 0.144 | 0.145 | +1% | 0.3 | 0.3 | -0% | 2.2 | 2.3 | 1/1 |  |
| sm-parallel t=64 | 0.154 | 0.156 | +1% | 0.4 | 0.4 | -2% | 2.2 | 2.3 | 1/1 |  |
| sm-parallel t=255 | 0.440 | 0.443 | +1% | 0.7 | 0.7 | +1% | 2.2 | 2.3 | 1/1 |  |
| sm-parallel t=256 | 0.443 | 0.443 | +0% | 0.7 | 0.7 | +0% | 2.2 | 2.3 | 1/1 |  |
| sm-parallel t=257 | 0.441 | 0.442 | +0% | 0.7 | 0.7 | -0% | 2.2 | 2.3 | 1/1 |  |
| sm-parallel t=1024 | 0.483 | 0.477 | -1% | 2.2 | 2.2 | -1% | 2.4 | 2.4 | 1/1 |  |
| sm-parallel t=10000 | 1.441 | 1.455 | +1% | 18.8 | 18.8 | -0% | 2.7 | 2.8 | 1/1 |  |
| io-group t=16 | 0.206 | 0.196 | -5% | 0.7 | 0.8 | +2% | 2.6 | 2.7 | 16/16 |  |
| io-group t=64 | 0.357 | 0.355 | -1% | 1.5 | 1.4 | -4% | 2.7 | 2.7 | 64/64 |  |
| io-group t=255 | 0.947 | 0.943 | -0% | 3.4 | 3.4 | -0% | 2.7 | 2.7 | 255/255 |  |
| io-group t=256 | 0.960 | 0.963 | +0% | 3.5 | 3.5 | +0% | 2.7 | 2.8 | 256/256 |  |
| io-group t=257 | 0.967 | 0.950 | -2% | 3.5 | 3.5 | +2% | 2.7 | 2.7 | 257/257 |  |
| io-group t=1024 | 3.389 | 3.327 | -2% | 11.9 | 11.4 | -4% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 31.116 | 31.205 | +0% | 109.7 | 110.8 | +1% | 2.7 | 2.8 | 10000/10000 |  |
| sm-fine t=1024 | 0.288 | 0.292 | +1% | 2.9 | 2.9 | -1% | 2.6 | 2.6 | 1/1 |  |
| sm-fine t=10000 | 1.551 | 1.532 | -1% | 22.4 | 22.4 | +0% | 2.8 | 2.8 | 1/1 |  |
| sm-fine t=100000 | 14.101 | 14.016 | -1% | 218.5 | 217.6 | -0% | 4.8 | 4.9 | 1/1 |  |

## Regressions (WORSE)

- none
