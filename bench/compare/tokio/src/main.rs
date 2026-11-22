// tokio side of the pyrlyn rt comparison. Same workloads as bench/rt.zig.
// Output: "<name> <ns_per_op> <allocs_per_op> <bytes_per_op>"
use std::alloc::{GlobalAlloc, Layout, System};
use std::hint::black_box;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::time::Instant;

struct Counting;
static ALLOCS: AtomicU64 = AtomicU64::new(0);
static BYTES: AtomicU64 = AtomicU64::new(0);
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 { ALLOCS.fetch_add(1, Relaxed); BYTES.fetch_add(l.size() as u64, Relaxed); System.alloc(l) }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) { System.dealloc(p, l) }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 { ALLOCS.fetch_add(1, Relaxed); BYTES.fetch_add(n as u64, Relaxed); System.realloc(p, l, n) }
}
#[global_allocator]
static GA: Counting = Counting;

fn snap() -> (u64, u64) { (ALLOCS.load(Relaxed), BYTES.load(Relaxed)) }
fn emit(name: &str, t0: Instant, ops: u64, a0: (u64, u64)) {
    let ns = t0.elapsed().as_nanos() as f64;
    let a1 = snap();
    println!("{} {:.3} {:.4} {:.2}", name, ns / ops as f64, (a1.0 - a0.0) as f64 / ops as f64, (a1.1 - a0.1) as f64 / ops as f64);
}

const SWITCHES: u64 = 20_000_000;
const SPAWN_N: u64 = 1_000_000;
const JOIN_ONE_N: u64 = 200_000;
const PINGPONG: u64 = 100_000;
const FANIN_N: u64 = 200_000;
const FANIN_CAP: usize = 1024;
const SKEW_N: u64 = 10_000;
const SKEW_LIGHT: u64 = 1_000;
const SKEW_HEAVY: u64 = 100_000;

fn rt(mt: bool) -> tokio::runtime::Runtime {
    if mt {
        let mut b = tokio::runtime::Builder::new_multi_thread();
        if let Ok(w) = std::env::var("WORKERS") { if let Ok(n) = w.parse::<usize>() { if n > 0 { b.worker_threads(n); } } }
        b.build().unwrap()
    } else { tokio::runtime::Builder::new_current_thread().build().unwrap() }
}

#[inline(never)]
fn lcg(iters: u64, seed: u64) -> u64 {
    let mut x = seed;
    for _ in 0..iters { x = x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407); }
    x
}

fn run(mt: bool, sfx: &'static str, which: &str) {
    let r = rt(mt);
    let all = which == "all";
    if all || which == "switch" {
        r.block_on(async {
            tokio::spawn(async move {
                let per = SWITCHES / 2;
                let a0 = snap();
                let t0 = Instant::now();
                let h1 = tokio::spawn(async move { for _ in 0..per { tokio::task::yield_now().await; } });
                let h2 = tokio::spawn(async move { for _ in 0..per { tokio::task::yield_now().await; } });
                h1.await.unwrap(); h2.await.unwrap();
                emit(&format!("switch_tokio_{}_yield", sfx), t0, SWITCHES, a0);
            }).await.unwrap();
        });
    }
    if all || which == "joinone" {
        r.block_on(async {
            tokio::spawn(async move {
                let a0 = snap();
                let t0 = Instant::now();
                let mut s = 0u64;
                for i in 0..JOIN_ONE_N { s = s.wrapping_add(tokio::spawn(async move { black_box(i.wrapping_mul(3).wrapping_add(1)) }).await.unwrap()); }
                black_box(s);
                emit(&format!("spawnjoin1_tokio_{}", sfx), t0, JOIN_ONE_N, a0);
            }).await.unwrap();
        });
    }
    if all || which == "spawn" {
        r.block_on(async {
            tokio::spawn(async move {
                let a0 = snap();
                let t0 = Instant::now();
                let mut hs = Vec::with_capacity(SPAWN_N as usize);
                for i in 0..SPAWN_N { hs.push(tokio::spawn(async move { black_box(i.wrapping_mul(3).wrapping_add(1)) })); }
                let mut s = 0u64;
                for h in hs { s = s.wrapping_add(h.await.unwrap()); }
                black_box(s);
                emit(&format!("spawn_tokio_{}", sfx), t0, SPAWN_N, a0);
            }).await.unwrap();
        });
    }
    if all || which == "pingpong" {
        r.block_on(async {
            tokio::spawn(async move {
                let (tx_a, mut rx_a) = tokio::sync::mpsc::channel::<u32>(1);
                let (tx_b, mut rx_b) = tokio::sync::mpsc::channel::<u32>(1);
                let a0 = snap();
                let t0 = Instant::now();
                let p = tokio::spawn(async move {
                    for _ in 0..PINGPONG { let v = rx_a.recv().await.unwrap(); tx_b.send(v + 1).await.unwrap(); }
                });
                let mut v = 0u32;
                for _ in 0..PINGPONG { tx_a.send(v).await.unwrap(); v = rx_b.recv().await.unwrap(); }
                p.await.unwrap();
                black_box(v);
                emit(&format!("pingpong_tokio_{}", sfx), t0, PINGPONG, a0);
            }).await.unwrap();
        });
    }
    if all || which == "fanin" {
        r.block_on(async {
            tokio::spawn(async move {
                let (tx, mut rx) = tokio::sync::mpsc::channel::<u64>(FANIN_CAP);
                let a0 = snap();
                let t0 = Instant::now();
                for i in 0..FANIN_N { let tx = tx.clone(); tokio::spawn(async move { tx.send(i).await.unwrap(); }); }
                let mut s = 0u64;
                for _ in 0..FANIN_N { s = s.wrapping_add(rx.recv().await.unwrap()); }
                black_box(s);
                emit(&format!("fanin_tokio_{}", sfx), t0, FANIN_N, a0);
                drop(tx);
            }).await.unwrap();
        });
    }
    if all || which == "skew" {
        r.block_on(async {
            tokio::spawn(async move {
                let a0 = snap();
                let t0 = Instant::now();
                let mut hs = Vec::with_capacity(SKEW_N as usize);
                for i in 0..SKEW_N { hs.push(tokio::spawn(async move { lcg(if i % 100 == 0 { SKEW_HEAVY } else { SKEW_LIGHT }, black_box(i)) })); }
                let mut s = 0u64;
                for h in hs { s = s.wrapping_add(h.await.unwrap()); }
                black_box(s);
                emit(&format!("skew_tokio_{}", sfx), t0, SKEW_N, a0);
            }).await.unwrap();
        });
    }
}

fn main() {
    let which = std::env::args().nth(1).unwrap_or_else(|| "all".into());
    run(false, "ct", &which);
    run(true, "mt", &which);
}
