# Benchmark: evented (debug-darwin-arm64)

- Date: 2026-11-10T05:37Z
- Machine: Ivan's Mac (Apple M3 Max)
- OS: macOS 27.0.1 (Darwin 27.0.0)
- CPU: Apple M3 Max, 16 logical CPUs
- Zig: 0.17.1, Debug
- Available RAM at start: 31078 MB

## std.Io.Threaded vs evented runtime (coroutines.evented)

Median of 5 runs; each run is a fresh process. RSS = peak resident set of that process.

| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| io-switch | 400000 | 935041875 | 2337.6 | 1 | 106 | 2 | 1 | 0 | 3.2 | 0.0 | 3.2 | 294 | 0 | 0 | 400002 | 0 | 0 | 0 |
| ev-switch | 400000 | 404511750 | 1011.3 | 1 | 62939136 | 2 | 1 | 0 | 63.6 | 0.0 | 63.6 | 4160 | 0 | 0 | 57004 | 0 | 0 | 0 |
| io-group | 10000 | 5250875 | 525.1 | 64 | 4608 | 16 | 1 | 0 | 3.9 | 0.0 | 3.9 | 399 | 0 | 0 | 152 | 0 | 0 | 0 |
| ev-group | 10000 | 237053042 | 23705.3 | 65 | 4027588608 | 16 | 1 | 0 | 99.0 | 0.0 | 99.0 | 246130 | 0 | 0 | 84 | 0 | 0 | 0 |
| io-dispatch | 100000 | 12704875 | 127.0 | 16 | 896 | 16 | 1 | 0 | 3.9 | 0.0 | 3.9 | 358 | 0 | 0 | 2154 | 0 | 0 | 0 |
| ev-dispatch | 100000 | 87010084 | 870.1 | 17 | 1006903296 | 16 | 1 | 0 | 964.4 | 0.0 | 964.4 | 61812 | 0 | 0 | 721 | 0 | 0 | 0 |

