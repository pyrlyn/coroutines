#!/usr/bin/env bash
# Runs every benchmark suite and writes one file per suite to bench/results/.
# Usage: bench/run.sh [path-to-bench-binary] [label]
set -euo pipefail
cd "$(dirname "$0")/.."
bin=${1:-zig-out/bin/bench}
label=${2:-$(uname -s | tr A-Z a-z)-$(uname -m)}
if [ "$bin" = zig-out/bin/bench ]; then zig build; fi
os=$(uname -sr)
if [ "$(uname -s)" = Darwin ]; then
  cpu=$(sysctl -n machdep.cpu.brand_string); ncpu=$(sysctl -n hw.ncpu); os="macOS $(sw_vers -productVersion) ($os)"
else
  cpu=$(lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}'); ncpu=$(nproc)
  os="$(. /etc/os-release; echo "$PRETTY_NAME") ($os)"
fi
zigv=${ZIG_VERSION:-$(zig version 2>/dev/null || echo 0.17.0)}
mkdir -p bench/results
if [ "$(uname -s)" = Darwin ]; then
  ps=$(sysctl -n hw.pagesize); avail=$(( ( $(vm_stat | awk '/Pages free|Pages inactive|Pages speculative/{gsub(/\./,"",$NF); s+=$NF} END{print s}') * ps ) / 1048576 ))
else
  avail=$(( $(awk '/MemAvailable/{print $2}' /proc/meminfo) / 1024 ))
fi
export MEM_AVAILABLE_MB=$avail
# 1024 worker processes need > 1024 pipe fds
ulimit -n 4096 2>/dev/null || true
for suite in ${SUITES:-switch spawn procs sweep}; do
  out=bench/results/$suite-$label.md
  {
    echo "# Benchmark: $suite ($label)"
    echo
    echo "- Date: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo "- Machine: ${MACHINE:-$(hostname -s)}"
    echo "- OS: $os"
    echo "- CPU: $cpu, $ncpu logical CPUs"
    echo "- Zig: $zigv, ReleaseFast"
    echo "- Available RAM at start: $avail MB"
    echo
    nice -n 10 "$bin" "$suite"
  } > "$out"
  echo "wrote $out"
done
