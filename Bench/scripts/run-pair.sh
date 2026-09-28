#!/bin/zsh
# v1.6.9 baseline benchmark: one host and one guest, two instances of the Release app on this
# Mac, playing a scenario unattended over 127.0.0.1.
#
#   run-pair.sh <scenario> [runs] [first-run-number]
#
#   BOLO_BENCH_APP      path to "Bolo 2026.app" (default: the Release build in DerivedData)
#   BOLO_BENCH_PORT     default 50555
#   BOLO_BENCH_LIMIT    seconds before a run is killed and marked invalid (default 300)
#   BOLO_BENCH_RUNS     where logs are collected (default: Bench/runs, not committed)
#   BOLO_BENCH_RECORD   0 to run without recording, for the observer-effect check (default 1)
#
# Runs are strictly serial. Each run's logs land in <runs>/<scenario>/run-NN/.

set -u
scenario=${1:?usage: run-pair.sh <scenario> [runs] [first-run-number]}
runs=${2:-1}
first=${3:-1}

here=${0:A:h}
root=${here:h:h}
port=${BOLO_BENCH_PORT:-50555}
limit=${BOLO_BENCH_LIMIT:-300}
record=${BOLO_BENCH_RECORD:-1}
out=${BOLO_BENCH_RUNS:-$root/Bench/runs}

app=${BOLO_BENCH_APP:-}
if [[ -z $app ]]; then
  products=$(xcodebuild -project "$root/Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" \
    -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
  app="$products/Bolo 2026.app"
fi
binary="$app/Contents/MacOS/Bolo 2026"
if [[ ! -x $binary ]]; then
  echo "run-pair: no app at $app (build Release first, or set BOLO_BENCH_APP)" >&2
  exit 64
fi

# The app is sandboxed: a log it created itself would land in its container, which this script
# may not read. So this script opens each log and passes it down as descriptor 3.

# Processor time used so far by a process, in seconds, as the system counts it. Measured from
# outside so it is there whether or not the app is recording.
cpu_seconds() {
  ps -o utime=,stime= -p $1 2>/dev/null | awk '{
    total = 0
    for (i = 1; i <= NF; i++) { n = split($i, part, ":"); t = 0; for (j = 1; j <= n; j++) t = t * 60 + part[j]; total += t }
    if (NF) printf "%.2f", total
  }'
}

failed=0
for ((n = first; n < first + runs; n++)); do
  number=$(printf '%02d' $n)
  id="$scenario-$(date +%Y%m%dT%H%M%S)-$number"
  dest="$out/$scenario/run-$number"
  rm -rf "$dest"
  mkdir -p "$dest"

  BOLO_BENCH=$record BOLO_BENCH_FD=3 BOLO_BENCH_ROLE=host BOLO_BENCH_SCENARIO=$scenario \
    BOLO_BENCH_PORT=$port BOLO_BENCH_RUN_ID=$id "$binary" 3> "$dest/host.jsonl" > "$dest/host.out" 2>&1 &
  host=$!
  sleep 2
  BOLO_BENCH=$record BOLO_BENCH_FD=3 BOLO_BENCH_ROLE=join BOLO_BENCH_SCENARIO=$scenario \
    BOLO_BENCH_PORT=$port BOLO_BENCH_RUN_ID=$id "$binary" 3> "$dest/join.jsonl" > "$dest/join.out" 2>&1 &
  guest=$!

  waited=0
  killed=0
  hostCpu=0
  guestCpu=0
  while kill -0 $host 2>/dev/null || kill -0 $guest 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    # The last reading before each process exits is its total, to within this second.
    reading=$(cpu_seconds $host); [[ -n $reading ]] && hostCpu=$reading
    reading=$(cpu_seconds $guest); [[ -n $reading ]] && guestCpu=$reading
    if ((waited >= limit)); then
      kill $host $guest 2>/dev/null
      killed=1
      break
    fi
  done
  wait $host 2>/dev/null; hostStatus=$?
  wait $guest 2>/dev/null; guestStatus=$?

  print -r -- "{\"runId\":\"$id\",\"scenario\":\"$scenario\",\"recording\":$record,\"port\":$port,\"seconds\":$waited,\"killed\":$killed,\"hostExit\":$hostStatus,\"guestExit\":$guestStatus,\"hostCpuSeconds\":$hostCpu,\"guestCpuSeconds\":$guestCpu,\"app\":\"$app\",\"binarySHA256\":\"$(shasum -a 256 "$binary" | cut -d' ' -f1)\",\"commit\":\"$(git -C "$root" rev-parse HEAD)\",\"dirty\":$([[ -n $(git -C "$root" status --porcelain) ]] && echo true || echo false),\"powerSource\":\"$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")\"}" > "$dest/run.json"

  logs=$(find "$dest" -name '*.jsonl' -size +0 | wc -l | tr -d ' ')
  echo "run-$number: ${waited}s host=$hostStatus guest=$guestStatus killed=$killed logs=$logs"
  if ((killed || hostStatus != 0 || guestStatus != 0)) || { ((record)) && ((logs != 2)); }; then
    failed=$((failed + 1))
  fi
  sleep 2
done

echo "$scenario: $runs run(s), $failed invalid"
exit $((failed > 0))
