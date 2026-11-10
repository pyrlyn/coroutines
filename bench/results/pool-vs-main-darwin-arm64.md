# Benchmark: pool vs main (darwin-arm64)

- Date: 2026-11-01T17:04Z
- Machine: Ivan's Mac, macOS 27.0.1, Apple M3 Max, 16 logical CPUs
- Zig: 0.17.0, ReleaseFast
- Load average at start / end: 9.7 / 11.0 (the Mac was in use; small differences are noise)
- Method: base = this branch's bench/main.zig built against main's `src/` (8b175b2); new = this branch. Each row: 11 runs per side, interleaved base/new, each a fresh process (`bench variant ...`). Medians shown. Flag: WORSE / better = median differs by >= 5% and the interquartile ranges do not overlap; ~noise = >= 5% but they overlap. CPU = user + sys of the whole variant incl. setup. RSS = peak resident set.

| scenario | base ms | new ms | time Δ | base CPU ms | new CPU ms | CPU Δ | base RSS MB | new RSS MB | allocs base/new | flags |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| sm-switch | 13.970 | 14.120 | +1% | 13.9 | 14.1 | +1% | 1.9 | 1.9 | 0/0 |  |
| io-switch | 717.586 | 720.831 | +0% | 732.4 | 743.5 | +2% | 2.0 | 2.0 | 1/1 |  |
| sequential | 16.676 | 16.638 | -0% | 16.7 | 16.6 | -0% | 1.9 | 1.9 | 0/0 |  |
| sm-1thread | 15.765 | 15.963 | +1% | 15.8 | 16.0 | +1% | 2.2 | 2.2 | 1/1 |  |
| procs2 | 11.179 | 11.151 | -0% | 0.4 | 0.4 | -6% | 2.2 | 2.1 | 0/0 |  |
| sm-parallel t=16 | 0.156 | 0.160 | +2% | 0.4 | 0.4 | -4% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=64 | 0.160 | 0.163 | +2% | 0.4 | 0.4 | +6% | 2.3 | 2.3 | 1/1 |  |
| sm-parallel t=255 | 0.469 | 0.472 | +1% | 0.7 | 0.7 | +2% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=256 | 0.475 | 0.477 | +0% | 0.7 | 0.7 | -1% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=257 | 0.473 | 0.474 | +0% | 0.7 | 0.7 | -0% | 2.3 | 2.2 | 1/1 |  |
| sm-parallel t=1024 | 0.507 | 0.496 | -2% | 2.4 | 2.2 | -8% | 2.5 | 2.4 | 1/1 |  |
| sm-parallel t=10000 | 1.553 | 1.517 | -2% | 18.9 | 18.7 | -1% | 2.7 | 2.7 | 1/1 |  |
| io-group t=16 | 0.200 | 0.214 | +7% | 0.8 | 0.9 | +18% | 2.6 | 2.6 | 16/16 |  |
| io-group t=64 | 0.347 | 0.359 | +4% | 1.4 | 1.4 | +3% | 2.7 | 2.7 | 64/64 |  |
| io-group t=255 | 0.891 | 0.972 | +9% | 3.3 | 3.6 | +10% | 2.8 | 2.7 | 255/255 | time ~noise, CPU ~noise |
| io-group t=256 | 0.939 | 0.980 | +4% | 3.6 | 3.8 | +5% | 2.8 | 2.7 | 256/256 |  |
| io-group t=257 | 0.972 | 0.976 | +0% | 3.7 | 3.7 | +1% | 2.7 | 2.7 | 257/257 |  |
| io-group t=1024 | 3.406 | 3.345 | -2% | 11.6 | 11.9 | +2% | 2.8 | 2.8 | 1024/1024 |  |
| io-group t=10000 | 31.293 | 31.381 | +0% | 105.8 | 104.7 | -1% | 2.8 | 2.7 | 10000/10000 |  |
| sm-repeat t=16 | 70.161 | 21.120 | -70% | 169.1 | 261.5 | +55% | 2.4 | 2.6 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-repeat t=256 | 233.610 | 202.129 | -13% | 357.4 | 569.9 | +59% | 2.4 | 2.6 | 1/1 | time better, CPU WORSE, RSS WORSE |
| sm-repeat t=1024 | 245.797 | 213.468 | -13% | 996.7 | 1152.0 | +16% | 2.6 | 2.6 | 1/1 | time better, CPU WORSE |
| sm-repeat t=10000 | 773.905 | 758.163 | -2% | 9338.0 | 9662.7 | +3% | 3.0 | 2.8 | 1/1 |  |

## Regressions (WORSE)

- sm-repeat t=16: CPU WORSE, RSS WORSE
- sm-repeat t=256: CPU WORSE, RSS WORSE
- sm-repeat t=1024: CPU WORSE
