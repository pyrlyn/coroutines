// Go side of the pyrlyn rt comparison. Same workloads as bench/rt.zig.
// Output: "<name> <ns_per_op> <allocs_per_op> <bytes_per_op>" (allocs via runtime.MemStats)
package main

import (
	"fmt"
	"os"
	"runtime"
	"sync"
	"time"
)

const (
	SWITCHES   = 20_000_000
	SPAWN_N    = 1_000_000
	JOIN_ONE_N = 200_000
	PINGPONG   = 100_000
	FANIN_N    = 200_000
	FANIN_CAP  = 1024
	SKEW_N     = 10_000
	SKEW_LIGHT = 1_000
	SKEW_HEAVY = 100_000
)

var sink uint64

func ms() (uint64, uint64) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return m.Mallocs, m.TotalAlloc
}

func emit(name string, t0 time.Time, ops uint64, a0, b0 uint64) {
	ns := float64(time.Since(t0).Nanoseconds())
	a1, b1 := ms()
	fmt.Printf("%s %.3f %.4f %.2f\n", name, ns/float64(ops), float64(a1-a0)/float64(ops), float64(b1-b0)/float64(ops))
}

//go:noinline
func lcg(iters, seed uint64) uint64 {
	x := seed
	for i := uint64(0); i < iters; i++ {
		x = x*6364136223846793005 + 1442695040888963407
	}
	return x
}

func run(sfx string, procs int, which string) {
	runtime.GOMAXPROCS(procs)
	all := which == "all"
	if all || which == "switch" {
		a0, b0 := ms()
		t0 := time.Now()
		var wg sync.WaitGroup
		wg.Add(2)
		for k := 0; k < 2; k++ {
			go func() {
				for i := 0; i < SWITCHES/2; i++ {
					runtime.Gosched()
				}
				wg.Done()
			}()
		}
		wg.Wait()
		emit("switch_go_"+sfx+"_yield", t0, SWITCHES, a0, b0)
	}
	if all || which == "joinone" {
		runtime.GC()
		done := make(chan uint64, 1)
		a0, b0 := ms()
		t0 := time.Now()
		var s uint64
		for i := uint64(0); i < JOIN_ONE_N; i++ {
			go func(i uint64) { done <- i*3 + 1 }(i)
			s += <-done
		}
		emit("spawnjoin1_go_"+sfx, t0, JOIN_ONE_N, a0, b0)
		sink = s
	}
	if all || which == "spawn" {
		runtime.GC()
		out := make([]uint64, SPAWN_N)
		a0, b0 := ms()
		t0 := time.Now()
		var wg sync.WaitGroup
		wg.Add(SPAWN_N)
		for i := 0; i < SPAWN_N; i++ {
			go func(i int) {
				out[i] = uint64(i)*3 + 1
				wg.Done()
			}(i)
		}
		wg.Wait()
		emit("spawn_go_"+sfx, t0, SPAWN_N, a0, b0)
		sink = out[SPAWN_N-1]
	}
	if all || which == "pingpong" {
		qa := make(chan uint32, 1)
		qb := make(chan uint32, 1)
		a0, b0 := ms()
		t0 := time.Now()
		done := make(chan struct{})
		go func() {
			for i := 0; i < PINGPONG; i++ {
				v := <-qa
				qb <- v + 1
			}
			close(done)
		}()
		var v uint32
		for i := 0; i < PINGPONG; i++ {
			qa <- v
			v = <-qb
		}
		<-done
		emit("pingpong_go_"+sfx, t0, PINGPONG, a0, b0)
		sink = uint64(v)
	}
	if all || which == "fanin" {
		runtime.GC()
		c := make(chan uint64, FANIN_CAP)
		a0, b0 := ms()
		t0 := time.Now()
		for i := uint64(0); i < FANIN_N; i++ {
			go func(i uint64) { c <- i }(i)
		}
		var s uint64
		for i := 0; i < FANIN_N; i++ {
			s += <-c
		}
		emit("fanin_go_"+sfx, t0, FANIN_N, a0, b0)
		sink = s
	}
	if all || which == "skew" {
		runtime.GC()
		out := make([]uint64, SKEW_N)
		a0, b0 := ms()
		t0 := time.Now()
		var wg sync.WaitGroup
		wg.Add(SKEW_N)
		for i := uint64(0); i < SKEW_N; i++ {
			go func(i uint64) {
				it := uint64(SKEW_LIGHT)
				if i%100 == 0 {
					it = SKEW_HEAVY
				}
				out[i] = lcg(it, i)
				wg.Done()
			}(i)
		}
		wg.Wait()
		emit("skew_go_"+sfx, t0, SKEW_N, a0, b0)
		sink = out[0]
	}
}

func main() {
	which := "all"
	if len(os.Args) > 1 {
		which = os.Args[1]
	}
	run("p1", 1, which)
	run("pN", runtime.NumCPU(), which)
}
