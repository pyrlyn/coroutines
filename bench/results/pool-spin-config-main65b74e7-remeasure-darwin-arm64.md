# Re-measure of rows flagged WORSE (non-RSS), main 65b74e7, darwin-arm64

21 interleaved runs per binary (main, event-wake = evcap, spin-config default = adcap), fresh process each, medians. Load average 5.4.

| scenario | main ms / CPU ms / RSS MB | event-wake | spin-config default |
|---|---|---|---|
| sm-repeat-gap t=16 | 35.315 / 5.10 / 1.98 | 35.522 / 5.54 / 2.36 | 35.498 / 5.61 / 2.38 |
| io-dispatch-big t=16 | 0.230 / 1.57 / 2.77 | 0.223 / 1.32 / 2.77 | 0.216 / 1.47 / 2.78 |
| io-group t=64 | 0.324 / 1.39 / 2.72 | 0.334 / 1.41 / 2.73 | 0.332 / 1.42 / 2.73 |

- sm-repeat-gap t=16: +0.45 ms CPU per process is spawning 15 pool threads once in `init` (200 runs of 16 tasks wake no thread with cap_wake), not idle spinning. RSS +0.4 MB = pool thread stacks.
- io-dispatch-big t=16 and io-group t=64: not reproduced (code identical to main); earlier flags were noise.
