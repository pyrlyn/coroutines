# `rt` vs tokio vs Go — Linux aarch64 (Lima `default`), after lazy driver start, 2026-11-10 10:33:59–10:37:48 EET

Same methodology as the macOS ABBA: 11 fresh-process runs, order A B B A A B B A A B B, median ns/op, phase-1 `rt` (`1152a15`, `rtp1`) in the same loop. Fix commit `2efdb67` (lazy driver start, local LIFO, `poll_seq` only after the driver is up).

* Host: Lima VM `default`, Ubuntu (`Linux 7.0.0-38-generic aarch64`), **4 vCPUs**, 4 GiB. Existing VM, config not changed. Binaries were cross-compiled on the Mac (Zig 0.17.1, `aarch64-linux-gnu`, ReleaseFast) and run in the guest.
* Multi-thread = CPU count (4), not 16: oversubscribing a 4-vCPU VM would not be comparable. tokio uses its default (4), Go `GOMAXPROCS=4`.
* **Load:** guest load average 0.06–1.98 (start 0.06 0.04 0.15, end 1.69 0.99 0.52). The guest was otherwise idle.

## ns per operation, median (min–max)

| workload | threads | pyrlyn before (Io.Threaded) | **pyrlyn rt** | tokio | Go | winner |
|---|---|---:|---:|---:|---:|---|
| spawn + join one | 1 | — | **48.2** (43.7–50.2) | 88.6 (82.0–91.7) | 223.7 (214.9–240.3) | rt, 1.8× vs tokio |
| spawn + join one | 4 | 21100 | **46.4** (43.2–51.6) | 239.0 (188.5–258.6) | 221.7 (214.0–233.5) | rt, 4.8× vs Go |
| spawn 1M, join all | 1 | — | **55.7** (46.4–62.6) | 132.1 (121.3–159.0) | 541.8 (439.3–574.6) | rt, 2.4× vs tokio |
| spawn 1M, join all | 4 | 95.9 (83.6–186.7) | **30.6** (25.6–32.0) | 310.0 (226.6–361.0) | 259.8 (181.1–371.9) | rt, 8.5× vs Go |
| channel ping-pong | 1 | — | **37.9** (34.3–39.5) | 89.0 (82.5–95.9) | 197.7 (182.1–210.3) | rt, 2.3× vs tokio |
| channel ping-pong | 4 | 20880 | **39.6** (37.5–42.4) | 264.2 (194.1–290.0) | 196.1 (189.6–208.5) | rt, 4.9× vs Go |
| fan-out / fan-in | 1 | — | **115.0** (83.5–154.9) | 185.4 (173.7–197.3) | 2107 (1925–2710) | rt, 1.6× vs tokio |
| fan-out / fan-in | 4 | — | **93.9** (68.0–100.4) | 637.4 (472.1–693.5) | 1444 (1394–1594) | rt, 6.8× vs tokio |
| skewed CPU work | 1 | — | **1810** (1615–1881) | 1904 (1680–1969) | 2936 (2772–3116) | rt, 1.1× vs tokio |
| skewed CPU work | 4 | — | **455.9** (430.4–495.8) | 571.1 (533.7–880.3) | 776.8 (668.8–820.9) | rt, 1.3× vs tokio |
| yield switch | 1 | — | **16.4** (15.4–16.7) | 53.9 (47.6–64.0) | 52.6 (48.9–54.8) | rt, 3.2× vs Go |
| yield switch | 4 | — | **11.5** (7.48–20.3) | 164.5 (129.6–194.8) | 120.2 (113.3–126.0) | rt, 10.5× vs Go |

`Seq` is within ~2 % of the hand-written ping-pong and spawn+join on this machine (spawn+join 1t **47.4** vs 48.2; 4t **46.9** vs 46.4; ping-pong 1t **37.5** vs 37.9; 4t **40.5** vs 39.6).

## vs phase-1 `rt` in the same loop

Every row is within 5 % of phase-1 `rt`. The previous 7-run at `58a0491` (driver started at init) had ping-pong +17–20 % and spawn 4t +11.1 %.

| workload | threads | phase-1 rt | **phase-2 rt (after fix)** | vs p1 after fix | vs p1 before fix (`58a0491`, 7-run) |
|---|---|---:|---:|---:|---:|
| spawn + join one | 1 | 50.2 (44.5–51.2) | **48.2** (43.7–50.2) | −3.9 % | +3.3 % |
| spawn + join one | 4 | 47.9 (45.1–50.1) | **46.4** (43.2–51.6) | −3.1 % | +1.0 % |
| spawn 1M, join all | 1 | 56.3 (51.1–63.5) | **55.7** (46.4–62.6) | −1.1 % | +4.1 % |
| spawn 1M, join all | 4 | 31.3 (26.2–32.5) | **30.6** (25.6–32.0) | −2.2 % | +11.1 % |
| channel ping-pong | 1 | 38.5 (35.5–43.3) | **37.9** (34.3–39.5) | −1.6 % | +17.0 % |
| channel ping-pong | 4 | 39.8 (37.4–42.9) | **39.6** (37.5–42.4) | −0.5 % | +20.3 % |
| fan-out / fan-in | 1 | 113.8 (97.6–170.7) | **115.0** (83.5–154.9) | +1.0 % | −2.1 % |
| fan-out / fan-in | 4 | 94.5 (68.0–108.3) | **93.9** (68.0–100.4) | −0.7 % | +4.3 % |
| skewed CPU work | 1 | 1859 (1666–1954) | **1810** (1615–1881) | −2.6 % | +2.0 % |
| skewed CPU work | 4 | 458.6 (431.0–492.0) | **455.9** (430.4–495.8) | −0.6 % | −0.1 % |
| yield switch | 1 | 16.5 (15.3–16.9) | **16.4** (15.4–16.7) | −0.6 % | +2.0 % |
| yield switch | 4 | 11.5 (8.22–15.9) | **11.5** (7.48–20.3) | −0.6 % | −2.6 % |

`rt` still wins every row against tokio and Go.

Raw log (load + 11 runs): [`rt-vs-tokio-go-linux-aarch64.raw.txt`](rt-vs-tokio-go-linux-aarch64.raw.txt).
