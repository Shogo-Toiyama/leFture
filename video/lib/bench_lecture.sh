#!/bin/zsh
# Path tracer cost benchmark for test/lecture.
# For each variant: render t=4.5 (wide) twice and t=1.5 (close-up) once at SPP samples,
# read the GPU-synced frame time the scene logs, and append to a JSON report.
#   usage: lib/bench_lecture.sh <out.json> <spp> "name|query" ...
cd "$(dirname "$0")/.."
OUT=$1; SPP=$2; shift 2
echo "[" > "$OUT"
first=1
for v in "$@"; do
  name=${v%%|*}; q=${v#*|}
  log=$(node lib/render.mjs test/lecture --stills 4.5,4.5,1.5 --query "spp=$SPP&dbg=1${q:+&$q}" 2>&1)
  ms=($(echo "$log" | grep -oE '\[lecture\] t=[0-9.]+ samples=[0-9]+ ms=[0-9]+' | grep -oE 'ms=[0-9]+' | cut -d= -f2))
  relaunch=$(echo "$log" | grep -c 'page error\|Target closed')
  # keep the steady-state wide still for visual comparison, drop the rest
  stills=($(echo "$log" | grep -oE 'still → [^ ]+' | cut -d' ' -f3))
  [ -n "${stills[2]}" ] && mv "${stills[2]}" "test/lecture/results/$(basename $OUT .json)_${name}_wide.png"
  [ -n "${stills[3]}" ] && mv "${stills[3]}" "test/lecture/results/$(basename $OUT .json)_${name}_close.png"
  rm -f "${stills[1]}"
  [ $first -eq 0 ] && echo "," >> "$OUT"; first=0
  printf '{"name":"%s","query":"%s","spp":%s,"wide_first_ms":%s,"wide_ms":%s,"close_ms":%s,"errors":%s}' \
    "$name" "$q" "$SPP" "${ms[1]:-null}" "${ms[2]:-null}" "${ms[3]:-null}" "$relaunch" >> "$OUT"
  echo "$name  wide=${ms[2]}ms  close=${ms[3]}ms  (${SPP}spp)  errors=$relaunch"
done
echo "]" >> "$OUT"
