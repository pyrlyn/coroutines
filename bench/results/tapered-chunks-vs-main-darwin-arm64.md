# Benchmark: tapered-chunks vs main (darwin-arm64)

- Date: 2026-11-01T16:58Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 9.2 / 8.8 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 14.097 | 14.119 | +0% | 14.1 | 14.1 | +0% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 798.155 | 784.843 | -2% | 827.7 | 804.9 | -3% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.728 | 16.513 | -1% | 16.7 | 16.5 | -1% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.623 | 15.807 | +1% | 15.6 | 15.7 | +1% | 2.1 | 2.2 | 1/1 |  |
| procs2 | 11.592 | 11.497 | -1% | 0.5 | 0.5 | -5% | 2.1 | 2.2 | 0/0 |  |
| sm-parallel t=16 | 0.167 | 0.166 | -0% | 0.4 | 0.4 | +8% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=64 | 0.184 | 0.199 | +8% | 0.6 | 0.7 | +25% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=255 | 0.496 | 0.220 | -56% | 0.9 | 1.3 | +44% | 2.3 | 2.5 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-parallel t=256 | 0.481 | 0.193 | -60% | 0.8 | 1.2 | +54% | 2.3 | 2.5 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-parallel t=257 | 0.478 | 0.235 | -51% | 0.8 | 1.4 | +69% | 2.3 | 2.5 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-parallel t=1024 | 0.525 | 0.402 | -23% | 2.3 | 2.6 | +12% | 2.4 | 2.5 | 1/1 | time better, CPU ~noise |
| sm-parallel t=10000 | 1.671 | 1.663 | -0% | 18.8 | 20.1 | +7% | 2.7 | 2.8 | 1/1 | CPU WORSE |
| io-group t=16 | 0.204 | 0.223 | +9% | 0.8 | 0.9 | +9% | 2.6 | 2.6 | 16/16 |  |
| io-group t=64 | 0.377 | 0.355 | -6% | 1.6 | 1.6 | +4% | 2.7 | 2.7 | 64/64 | time ~noise |
| io-group t=255 | 1.020 | 1.011 | -1% | 3.7 | 3.6 | -4% | 2.7 | 2.7 | 255/255 |  |
| io-group t=256 | 0.996 | 1.051 | +6% | 3.8 | 4.4 | +14% | 2.7 | 2.7 | 256/256 | time ~noise, CPU ~noise |
| io-group t=257 | 1.042 | 1.015 | -3% | 4.1 | 3.7 | -11% | 2.6 | 2.8 | 257/257 | CPU ~noise, RSS WORSE |
| io-group t=1024 | 3.528 | 3.411 | -3% | 12.0 | 11.7 | -3% | 2.7 | 2.7 | 1024/1024 |  |
| io-group t=10000 | 32.616 | 31.857 | -2% | 104.3 | 104.7 | +0% | 2.7 | 2.7 | 10000/10000 |  |
| sm-skew t=1024 | 0.796 | 0.422 | -47% | 3.2 | 3.8 | +19% | 2.4 | 2.6 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-skew t=10000 | 2.587 | 2.400 | -7% | 29.5 | 30.7 | +4% | 2.7 | 2.8 | 1/1 | time ~noise |
| sm-skew t=100000 | 21.507 | 21.868 | +2% | 284.7 | 283.8 | -0% | 4.8 | 4.9 | 1/1 |  |

## Regressions (WORSE)

- sm-parallel t=255: CPU WORSE, RSS WORSE
- sm-parallel t=256: CPU WORSE, RSS WORSE
- sm-parallel t=257: CPU WORSE, RSS WORSE
- sm-parallel t=10000: CPU WORSE
- io-group t=257: RSS WORSE
- sm-skew t=1024: CPU WORSE, RSS WORSE
