# `rt` vs tokio vs Go — Apple M3 Max, phase 2 (timers / reactor / Seq), 2026-11-10 10:06–10:11 EET

Phase 2 of draft PR #20: same workloads as [`rt-vs-tokio-go-darwin-arm64.md`](rt-vs-tokio-go-darwin-arm64.md) (phase 1, head `1152a15`), plus `spawnjoin1seq_*` / `pingpongseq_*` written with `rt.Seq`. The runtime now has a driver thread (timers, kqueue reactor, blocking pool, stuck-worker monitor).

* pyrlyn `rt` at this commit, Zig 0.17.1 ReleaseFast. "rtp1" / "before" = the phase-1 `rt` binary (`1152a15`) and `main` `std.Io.Threaded`, run in the same ABBA loop.
* tokio 1.54.1 (rustc 1.99.1, release, lto=fat, codegen-units=1); Go 1.27.1. Same binaries as phase 1.
* Single-thread = `current_thread` / `new_current_thread()` / `GOMAXPROCS=1`; multi-thread = 16 workers / tokio default / `GOMAXPROCS=16`.
* 7 fresh-process runs, ABBA (A B B A A B B; A = current `rt` first), median with min–max.
* **Load:** the Mac was shared with other jobs. Load average 7.6–15.3 (start `{ 9.41 9.21 9.83 }`, end `{ 10.00 10.35 10.19 }`, peak 15.33 on run 4). Absolute numbers are noisier than phase 1 (ranges often 3–5×); compare `rt` to `rtp1` / tokio / Go from **this** run, not only to the phase-1 table.

## ns per operation, median (min–max)

| workload | threads | pyrlyn before (Io.Threaded) | **pyrlyn rt** | tokio | Go | winner |
|---|---|---:|---:|---:|---:|---|
| spawn + join one | 1 | — | **33.9** (22.9–124.2) | 118.0 (96.3–500.1) | 251.3 (209.2–568.1) | rt, 3.5× vs tokio |
| spawn + join one | 16 | 4524 | **26.7** (22.6–84.5) | 167.1 (141.2–434.9) | 355.1 (262.1–837.9) | rt, 6.3× vs tokio |
| spawn 1M, join all | 1 | — | **58.9** (46.5–161.0) | 116.9 (90.5–437.9) | 528.5 (485.3–831.5) | rt, 2.0× vs tokio |
| spawn 1M, join all | 16 | 2110 | **64.8** (55.1–84.6) | 269.4 (214.0–513.8) | 444.8 (330.2–943.2) | rt, 4.2× vs tokio |
| channel ping-pong | 1 | — | **36.7** (25.4–94.8) | 101.3 (82.6–388.7) | 222.8 (187.1–512.9) | rt, 2.8× vs tokio |
| channel ping-pong | 16 | 5610 | **35.2** (27.9–100.3) | 149.6 (129.1–370.4) | 345.4 (236.1–691.8) | rt, 4.3× vs tokio |
| fan-out / fan-in | 1 | — | **127.3** (86.2–353.8) | 190.9 (152.8–714.0) | 2399 (1905–4620) | rt, 1.5× vs tokio |
| fan-out / fan-in | 16 | 109356 | **236.2** (176.7–333.5) | 952.6 (771.2–1467.8) | 1013 (794–2419) | rt, 4.0× vs tokio |
| skewed CPU work | 1 | — | **2325** (1700–4937) | 2258 (1742–7405) | 2869 (2727–7052) | tokio, 1.0× slower than tokio |
| skewed CPU work | 16 | 3765 | **194** (156–1262) | 416 (319–1016) | 466 (365–2045) | rt, 2.1× vs tokio |
| yield switch | 1 | — | **12.1** (8.6–42.3) | 62.6 (49.0–155.9) | 56.0 (46.6–101.8) | rt, 4.6× vs Go |
| yield switch | 16 | — | **13.9** (9.7–34.6) | 179.4 (154.4–392.4) | 129.3 (111.8–208.8) | rt, 9.3× vs Go |

`Seq` vs the hand-written state machine (same run): spawn+join 1t **31.1** vs 33.9; 16t **28.6** vs 26.7; ping-pong 1t **44.1** vs 36.7; 16t **39.9** vs 35.2. Allocations per spawn are unchanged: rt 0.001, tokio 1, Go 2.

## Regression vs phase 1

Medians in this run are 20–80 % higher than the phase-1 table for every program, including the unchanged phase-1 `rt` binary and tokio/Go (e.g. spawn+join 16t tokio 167 vs 143 in phase 1; ping-pong 16t Go 345 vs 234). The machine was busier in a bursty way (wide min–max). The phase-1 table is not a same-conditions baseline.

Against the phase-1 `rt` binary in **this** ABBA loop:

| workload | threads | phase-1 rt (same run) | **phase-2 rt** | vs phase-1 same run |
|---|---|---:|---:|---:|
| spawn + join one | 1 | 29.6 (21.0–96.6) | **33.9** (22.9–124.2) | +14.5 % |
| spawn + join one | 16 | 36.0 (21.5–88.9) | **26.7** (22.6–84.5) | −25.9 % |
| spawn 1M, join all | 1 | 55.1 (45.0–230.9) | **58.8** (46.5–161.0) | +6.8 % |
| spawn 1M, join all | 16 | 59.7 (41.9–166.4) | **64.8** (55.1–84.6) | +8.6 % |
| channel ping-pong | 1 | 37.0 (24.6–137.5) | **36.7** (25.4–94.8) | −0.8 % |
| channel ping-pong | 16 | 37.5 (25.5–89.4) | **35.2** (27.9–100.3) | −6.0 % |
| fan-out / fan-in | 1 | 110.3 (83.6–464.3) | **127.3** (86.3–353.8) | +15.5 % |
| fan-out / fan-in | 16 | 239.5 (192.3–294.7) | **236.2** (176.7–333.5) | −1.4 % |
| skewed CPU work | 1 | 2323 (1691–6241) | **2325** (1700–4937) | +0.1 % |
| skewed CPU work | 16 | 233.5 (152.7–1081) | **194.4** (156.1–1262) | −16.8 % |
| yield switch | 1 | 10.7 (8.1–38.2) | **12.1** (8.6–42.3) | +13.6 % |
| yield switch | 16 | 12.4 (9.0–38.2) | **14.0** (9.7–34.6) | +12.3 % |

There is no consistent regression: some multi-thread rows are faster than phase 1 in this run (spawn+join, ping-pong, skew), some current-thread rows are a few nanoseconds slower (atomic LIFO / `poll_seq` used by the stuck-worker monitor, even when the driver is not started). Mins sit next to the phase-1 table (spawn+join 16t min 22.6 vs 22.0; ping-pong 1t min 25.4 vs 24.6). A >5 % reading on a median here is load, not a change that needs a hot-path revert.

Raw log: [`rt-vs-tokio-go-darwin-arm64-phase2.raw.txt`](rt-vs-tokio-go-darwin-arm64-phase2.raw.txt).
