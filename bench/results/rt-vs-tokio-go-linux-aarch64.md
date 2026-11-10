# `rt` vs tokio vs Go — Linux aarch64 (Lima `default`), 2026-11-10 10:03–10:06 EET

Same methodology as the macOS ABBA: 7 fresh-process runs, order A B B A A B B, median ns/op, phase-1 `rt` (`1152a15`, `rtp1`) in the same loop.

* Host: Lima VM `default`, Ubuntu (`Linux 7.0.0-38-generic aarch64`), **4 vCPUs**, 4 GiB. Existing VM, config not changed. Binaries were cross-compiled on the Mac (Zig 0.17.1, `aarch64-linux-gnu`, ReleaseFast) and run in the guest.
* Multi-thread = CPU count (4), not 16: oversubscribing a 4-vCPU VM would not be comparable. tokio uses its default (4), Go `GOMAXPROCS=4`.
* **Load:** guest load average 0.22–1.93 (start 0.22 0.78 0.63, end 1.93 1.27 0.84). The guest was otherwise idle; the host Mac still had other jobs (load ~8–10).
* The first Linux attempt of this binary failed every multi-thread run with `error.Unexpected`. Cause: the driver thread was spawned with a 256 KiB stack; when the bench links libc, `pthread_create` fails because `std.options.signal_stack_size` is also 256 KiB. The driver stack is now 1 MiB (same as a worker). Tests were not affected: they do not link libc.

## ns per operation, median (min–max)

| workload | threads | pyrlyn before (Io.Threaded) | **pyrlyn rt** | tokio | Go | winner |
|---|---|---:|---:|---:|---:|---|
| spawn + join one | 1 | — | **47.2** (46.0–73.8) | 93.0 (84.7–123.8) | 250.2 (222.6–424.6) | rt, 2.0× vs tokio |
| spawn + join one | 4 | 23312 | **47.2** (43.5–77.3) | 285.9 (244.4–332.7) | 252.4 (208.9–391.7) | rt, 5.4× vs Go |
| spawn 1M, join all | 1 | — | **62.5** (54.8–93.7) | 135.1 (122.3–206.4) | 575.1 (539.1–748.5) | rt, 2.2× vs tokio |
| spawn 1M, join all | 4 | 107 | **34.9** (31.9–51.4) | 325.5 (272.4–513.9) | 301.0 (238.0–479.6) | rt, 8.6× vs Go |
| channel ping-pong | 1 | — | **45.9** (43.8–75.4) | 93.3 (88.2–165.4) | 193.6 (187.6–346.3) | rt, 2.0× vs tokio |
| channel ping-pong | 4 | 22522 | **47.9** (45.3–86.4) | 274.4 (270.5–403.7) | 225.6 (186.3–388.9) | rt, 4.7× vs Go |
| fan-out / fan-in | 1 | — | **134.1** (114.8–207.8) | 200.0 (178.5–343.1) | 2233 (1872–3439) | rt, 1.5× vs tokio |
| fan-out / fan-in | 4 | — | **96.0** (86.2–170.0) | 662.6 (574.2–1098.8) | 1559 (1396–2265) | rt, 6.9× vs tokio |
| skewed CPU work | 1 | — | **1773** (1702–2862) | 1951 (1775–3341) | 2880 (2677–4918) | rt, 1.1× vs tokio |
| skewed CPU work | 4 | — | **453** (436–843) | 697 (518–1001) | 829 (721–1341) | rt, 1.5× vs tokio |
| yield switch | 1 | — | **16.0** (15.5–27.4) | 56.4 (50.7–80.3) | 55.4 (50.6–80.7) | rt, 3.5× vs Go |
| yield switch | 4 | — | **11.7** (10.6–16.5) | 192.1 (155.0–220.2) | 141.0 (119.7–197.0) | rt, 12.0× vs Go |

`Seq` is within 1 % of the hand-written ping-pong and spawn+join on this machine (e.g. ping-pong 4t **46.7** vs 47.9).

## vs phase-1 `rt` in the same loop

| workload | threads | phase-1 rt | **phase-2 rt** | vs phase-1 |
|---|---|---:|---:|---:|
| spawn + join one | 1 | 45.7 (44.6–69.4) | **47.2** (46.0–73.8) | +3.3 % |
| spawn + join one | 4 | 46.7 (45.1–70.8) | **47.2** (43.5–77.3) | +1.0 % |
| spawn 1M, join all | 1 | 60.0 (52.8–78.2) | **62.5** (54.8–93.7) | +4.1 % |
| spawn 1M, join all | 4 | 31.4 (29.6–42.4) | **34.9** (31.9–51.4) | +11.1 % |
| channel ping-pong | 1 | 39.2 (36.8–55.4) | **45.9** (43.8–75.4) | +17.0 % |
| channel ping-pong | 4 | 39.8 (38.6–65.4) | **47.9** (45.3–86.4) | +20.3 % |
| fan-out / fan-in | 1 | 137.0 (115.0–173.1) | **134.1** (114.8–207.8) | −2.1 % |
| fan-out / fan-in | 4 | 92.0 (82.7–131.4) | **96.0** (86.2–170.0) | +4.3 % |
| skewed CPU work | 1 | 1738 (1674–2652) | **1773** (1702–2862) | +2.0 % |
| skewed CPU work | 4 | 453 (437–843) | **453** (436–843) | −0.1 % |
| yield switch | 1 | 15.7 (15.5–27.5) | **16.0** (15.5–27.4) | +2.0 % |
| yield switch | 4 | 12.0 (9.4–14.5) | **11.7** (10.6–16.4) | −2.6 % |

Ping-pong (and spawn on 4 threads) is clearly slower than phase 1 on this 4-vCPU VM. A multi-thread runtime now starts a driver thread at `init` (epoll + 1 ms stuck-worker monitor), so five threads share four vCPUs; ping-pong is a two-task LIFO path that does not need that thread. Atomic LIFO/`poll_seq` (so the monitor can steal a stuck worker's private tasks) also sit on that path. The other rows stay within ~5 %. `rt` still wins every row against tokio and Go.

Raw log: [`rt-vs-tokio-go-linux-aarch64.raw.txt`](rt-vs-tokio-go-linux-aarch64.raw.txt).
