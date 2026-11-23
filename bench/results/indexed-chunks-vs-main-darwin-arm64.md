# Benchmark: indexed-chunks vs main (darwin-arm64)

- Date: 2026-11-01T16:58Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 8.4 / 7.8 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.344 | 14.226 | -1% | 14.3 | 14.2 | -1% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 691.673 | 661.566 | -4% | 704.1 | 672.9 | -4% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.945 | 16.858 | -1% | 16.9 | 16.8 | -0% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.539 | 15.539 | +0% | 15.5 | 15.5 | -0% | 2.1 | 2.1 | 1/1 |  |
| procs2 | 11.523 | 11.401 | -1% | 0.4 | 0.5 | +7% | 2.1 | 2.1 | 0/0 |  |
| sm-parallel t=16 | 0.182 | 0.172 | -6% | 0.4 | 0.4 | -7% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=64 | 0.170 | 0.183 | +8% | 0.5 | 0.5 | +7% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=255 | 0.466 | 0.468 | +1% | 0.7 | 0.7 | +0% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=256 | 0.499 | 0.472 | -5% | 0.8 | 0.8 | -6% | 2.3 | 2.3 | 1/1 | time better |
| sm-parallel t=257 | 0.477 | 0.494 | +4% | 0.8 | 0.8 | -3% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=1024 | 0.516 | 0.510 | -1% | 2.1 | 2.1 | -2% | 2.4 | 2.4 | 1/1 |  |
| sm-parallel t=10000 | 1.781 | 1.759 | -1% | 18.6 | 18.6 | -0% | 2.7 | 2.7 | 1/1 |  |
| io-group t=16 | 0.214 | 0.213 | -0% | 0.9 | 1.0 | +7% | 2.6 | 2.7 | 16/16 |  |
| io-group t=64 | 0.373 | 0.385 | +3% | 1.7 | 1.6 | -1% | 2.7 | 2.7 | 64/64 |  |
| io-group t=255 | 1.123 | 0.939 | -16% | 3.8 | 3.4 | -10% | 2.7 | 2.7 | 255/255 | time better, CPU ~noise |
| io-group t=256 | 0.953 | 1.007 | +6% | 3.3 | 3.5 | +5% | 2.6 | 2.7 | 256/256 | time ~noise |
| io-group t=257 | 1.014 | 0.983 | -3% | 3.6 | 3.7 | +4% | 2.7 | 2.7 | 257/257 |  |
| io-group t=1024 | 3.463 | 3.475 | +0% | 11.9 | 11.8 | -1% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 32.410 | 31.342 | -3% | 105.4 | 104.0 | -1% | 2.7 | 2.7 | 10000/10000 |  |
| sm-big t=256 | 0.576 | 0.525 | -9% | 0.9 | 0.9 | +1% | 2.4 | 2.4 | 1/1 | time better |
| sm-big t=1024 | 0.657 | 0.599 | -9% | 2.6 | 2.3 | -12% | 2.9 | 2.8 | 1/1 | time better, CPU better |
| sm-big t=10000 | 2.374 | 2.170 | -9% | 23.0 | 20.8 | -9% | 7.3 | 7.3 | 1/1 | time better, CPU better |

## Regressions (WORSE)

- none
