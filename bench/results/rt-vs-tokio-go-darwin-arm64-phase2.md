# `rt` vs tokio vs Go — Apple M3 Max, phase 2 after lazy driver start, 2026-11-10 10:38–10:43 EET

Draft PR #20, fix commit `2efdb67`: the driver thread now starts only when a timer or `IoSource` is first used, the LIFO slot is a plain owner-only pointer again, and `poll_seq` is updated only after the driver is up. Same workloads as [`rt-vs-tokio-go-darwin-arm64.md`](rt-vs-tokio-go-darwin-arm64.md) (phase 1, head `1152a15`), plus `spawnjoin1seq_*` / `pingpongseq_*` written with `rt.Seq`.

* pyrlyn `rt` at `2efdb67`, Zig 0.17.1 ReleaseFast. "rtp1" / "before" = the phase-1 `rt` binary (`1152a15`) and `main` `std.Io.Threaded`, run in the same ABBA loop.
* tokio 1.54.1 (rustc 1.99.1, release, lto=fat, codegen-units=1); Go 1.27.1. Same binaries as phase 1.
* Single-thread = `current_thread` / `new_current_thread()` / `GOMAXPROCS=1`; multi-thread = 16 workers / tokio default / `GOMAXPROCS=16`.
* 11 fresh-process runs, ABBA (A B B A A B B A A B B; A = current `rt` first), median with min–max.
* **Load:** start { 7.64 11.95 13.28 }, end { 7.99 10.22 12.18 }, peak 13.51 on run 3 (Apple M3 Max, 16 CPUs). A first 11-run at 10:26–10:33 EET hit a load spike of 35.2 and widened some medians (spawn+join 1t was +9 % vs p1 there, pairwise median only +1.6 %); this quieter rerun is the table below.

## ns per operation, median (min–max)

| workload | threads | pyrlyn before (Io.Threaded) | **pyrlyn rt** | tokio | Go | winner |
|---|---|---:|---:|---:|---:|---|
| spawn + join one | 1 | — | **21.7** (20.4–24.2) | 98.7 (95.0–104.9) | 211.0 (207.3–225.1) | rt, 4.6× vs tokio |
| spawn + join one | 16 | 3743 | **21.7** (21.3–23.3) | 147.0 (140.8–155.4) | 257.3 (237.1–270.2) | rt, 6.8× vs tokio |
| spawn 1M, join all | 1 | — | **44.9** (40.9–48.1) | 91.2 (87.2–99.0) | 490.2 (476.4–530.0) | rt, 2.0× vs tokio |
| spawn 1M, join all | 16 | 1905 | **43.6** (30.9–49.5) | 227.8 (211.3–245.2) | 315.1 (276.6–364.1) | rt, 5.2× vs tokio |
| channel ping-pong | 1 | — | **24.8** (23.9–26.0) | 82.9 (78.9–89.9) | 191.8 (188.4–203.0) | rt, 3.3× vs tokio |
| channel ping-pong | 16 | 4263 | **25.1** (24.4–25.9) | 127.6 (119.5–136.6) | 223.4 (211.4–241.0) | rt, 5.1× vs tokio |
| fan-out / fan-in | 1 | — | **93.0** (84.0–107.8) | 162.4 (151.3–214.0) | 2037 (1742–2732) | rt, 1.7× vs tokio |
| fan-out / fan-in | 16 | 68421 | **183.4** (137.5–221.1) | 797.7 (741.6–864.9) | 787.1 (776.9–851.2) | rt, 4.3× vs Go |
| skewed CPU work | 1 | — | **1705** (1648–1778) | 1737 (1675–2006) | 2669 (2582–3083) | rt, 1.0× vs tokio |
| skewed CPU work | 16 | 3546 | **159.7** (146.1–352.1) | 327.8 (297.7–396.8) | 352.1 (315.7–554.8) | rt, 2.1× vs tokio |
| yield switch | 1 | — | **8.00** (7.89–8.94) | 49.4 (48.4–51.7) | 46.6 (46.3–47.5) | rt, 5.8× vs Go |
| yield switch | 16 | — | **9.91** (7.66–12.0) | 144.2 (135.0–205.2) | 109.4 (87.6–111.3) | rt, 11.0× vs Go |

`Seq` vs the hand-written state machine (same run): spawn+join 1t **21.7** vs 21.7; 16t **22.0** vs 21.7; ping-pong 1t **32.5** vs 24.8; 16t **32.9** vs 25.1. Allocations per spawn are unchanged: rt 0.001, tokio 1, Go 2.

## Regression vs phase-1 `rt` in the same loop

Every row is within 5 % of phase-1 `rt` (the gate). Compare these percentages to the 7-run table from `58a0491` (driver started at init, atomic LIFO / `poll_seq` on every poll), which had several rows above 5 %.

| workload | threads | phase-1 rt (same run) | **phase-2 rt (after fix)** | vs p1 after fix | vs p1 before fix (`58a0491`, 7-run) |
|---|---|---:|---:|---:|---:|
| spawn + join one | 1 | 21.7 (20.8–23.3) | **21.7** (20.4–24.2) | −0.3 % | +14.5 % |
| spawn + join one | 16 | 22.0 (21.5–30.2) | **21.7** (21.3–23.3) | −1.2 % | −25.9 % |
| spawn 1M, join all | 1 | 43.2 (41.0–48.8) | **44.9** (40.9–48.1) | +3.9 % | +6.8 % |
| spawn 1M, join all | 16 | 44.7 (37.3–48.9) | **43.6** (30.9–49.5) | −2.5 % | +8.6 % |
| channel ping-pong | 1 | 25.0 (23.6–25.4) | **24.8** (23.9–26.0) | −0.6 % | −0.8 % |
| channel ping-pong | 16 | 25.6 (24.2–27.7) | **25.1** (24.4–25.9) | −2.1 % | −6.0 % |
| fan-out / fan-in | 1 | 93.6 (83.6–101.1) | **93.0** (84.0–107.8) | −0.6 % | +15.5 % |
| fan-out / fan-in | 16 | 183.7 (113.4–213.1) | **183.4** (137.5–221.1) | −0.2 % | −1.4 % |
| skewed CPU work | 1 | 1692 (1673–1802) | **1705** (1648–1778) | +0.8 % | +0.1 % |
| skewed CPU work | 16 | 166.5 (152.8–190.0) | **159.7** (146.1–352.1) | −4.1 % | −16.8 % |
| yield switch | 1 | 8.03 (7.92–8.92) | **8.00** (7.89–8.94) | −0.3 % | +13.6 % |
| yield switch | 16 | 10.6 (9.19–12.9) | **9.91** (7.66–12.0) | −6.5 % | +12.3 % |

Raw log (load + 11 runs): [`rt-vs-tokio-go-darwin-arm64-phase2.raw.txt`](rt-vs-tokio-go-darwin-arm64-phase2.raw.txt).
