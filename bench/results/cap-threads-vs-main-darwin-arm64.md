# Benchmark: cap-threads vs main (darwin-arm64)

- Date: 2026-11-01T17:02Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 17.0 / 14.2 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.090 | 14.107 | +0% | 14.1 | 14.1 | -0% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 720.751 | 738.599 | +2% | 725.3 | 748.5 | +3% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.744 | 16.704 | -0% | 16.7 | 16.7 | -0% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.227 | 15.306 | +1% | 15.2 | 15.3 | +1% | 2.1 | 2.1 | 1/1 |  |
| procs2 | 11.224 | 11.275 | +0% | 0.5 | 0.4 | -3% | 2.1 | 2.2 | 0/0 |  |
| sm-parallel t=16 | 0.167 | 0.028 | -83% | 0.4 | 0.0 | -92% | 2.3 | 1.9 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=64 | 0.175 | 0.108 | -39% | 0.5 | 0.1 | -76% | 2.3 | 1.9 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=255 | 0.468 | 0.397 | -15% | 0.7 | 0.4 | -46% | 2.3 | 1.9 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=256 | 0.478 | 0.398 | -17% | 0.8 | 0.4 | -48% | 2.3 | 1.9 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=257 | 0.478 | 0.419 | -12% | 0.8 | 0.4 | -46% | 2.3 | 2.0 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=1024 | 0.503 | 0.467 | -7% | 2.0 | 1.7 | -16% | 2.4 | 2.1 | 1/1 | time better, CPU better, RSS better |
| sm-parallel t=10000 | 1.595 | 1.623 | +2% | 19.0 | 18.9 | -1% | 2.7 | 2.7 | 1/1 |  |
| io-group t=16 | 0.202 | 0.233 | +15% | 1.0 | 0.9 | -8% | 2.6 | 2.6 | 16/16 | time ~noise |
| io-group t=64 | 0.407 | 0.354 | -13% | 1.7 | 1.4 | -15% | 2.7 | 2.7 | 64/64 | time ~noise, CPU ~noise |
| io-group t=255 | 1.387 | 1.046 | -25% | 4.7 | 4.0 | -16% | 2.7 | 2.7 | 255/255 | time ~noise, CPU ~noise |
| io-group t=256 | 1.101 | 1.120 | +2% | 3.9 | 3.9 | +1% | 2.7 | 2.6 | 256/256 |  |
| io-group t=257 | 0.964 | 0.993 | +3% | 3.4 | 3.6 | +6% | 2.7 | 2.7 | 257/257 | CPU ~noise |
| io-group t=1024 | 3.716 | 3.590 | -3% | 12.2 | 12.4 | +1% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 32.092 | 34.325 | +7% | 103.0 | 109.6 | +6% | 2.9 | 2.8 | 10000/10000 | time ~noise, CPU ~noise |

## Regressions (WORSE)

- none
