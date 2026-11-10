#!/usr/bin/env bash
# 7 fresh-process runs of every bench binary, sequential, interleaved.
# Raw lines -> logs/raw.txt ("<run> <name> <ns/op> <allocs/op> <bytes/op>"), load -> logs/load.txt
set -u
cd "$(dirname "$0")"; mkdir -p logs bin
cp repo/zig-out/bin/bench-rt bin/; cp cargo-target/release/bench-tokio bin/; cp bench-go/bench-go bin/; cp bench-before/zig-out/bin/bench-before bin/
: > logs/raw.txt; : > logs/load.txt
RUNS=${RUNS:-7}
for r in $(seq 1 $RUNS); do
  case $r in 1|4|5) ord=A;; *) ord=B;; esac
  echo "run $r order=$ord $(date +%H:%M:%S) $(sysctl -n vm.loadavg)" >> logs/load.txt
  # ABBA order over 7 runs: A B B A A B B (A = rt first, B = reverse).
  case $r in 1|4|5) order="bin/bench-rt bin/bench-tokio bin/bench-go bin/bench-before";; *) order="bin/bench-before bin/bench-go bin/bench-tokio bin/bench-rt";; esac
  for b in $order; do
    "$b" 2>&1 | sed "s/^/$r /" >> logs/raw.txt
  done
done
echo "end $(date +%H:%M:%S) $(sysctl -n vm.loadavg)" >> logs/load.txt
python3 aggregate.py > logs/summary.md
