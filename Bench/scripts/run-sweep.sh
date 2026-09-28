#!/bin/zsh
# v1.6.9 baseline benchmark: the scaling sweep. One instance of the Release app hosting, and
# N-1 synthetic guests from BoloBenchSwarm in one other process. Only the host is measured.
#
#   run-sweep.sh <players> [runs] [first-run-number]
#
#   BOLO_BENCH_APP      path to "Bolo 2026.app" (default: the Release build in DerivedData)
#   BOLO_BENCH_SWARM    path to BoloBenchSwarm (default: .build/release/BoloBenchSwarm)
#   BOLO_BENCH_PORT     default 50555
#   BOLO_BENCH_LIMIT    seconds before a run is killed and marked invalid (default 300)
#   BOLO_BENCH_RUNS     where logs are collected (default: Bench/runs, not committed)
#
# Runs are strictly serial. Each run's logs land in <runs>/sweep-nNN/run-NN/.

set -u
players=${1:?usage: run-sweep.sh <players 2-16> [runs] [first-run-number]}
runs=${2:-1}
first=${3:-1}
if ((players < 2 || players > 16)); then
  echo "run-sweep: players must be 2 to 16" >&2
  exit 64
fi

here=${0:A:h}
root=${here:h:h}
port=${BOLO_BENCH_PORT:-50555}
limit=${BOLO_BENCH_LIMIT:-300}
out=${BOLO_BENCH_RUNS:-$root/Bench/runs}
swarm=${BOLO_BENCH_SWARM:-$root/.build/release/BoloBenchSwarm}
tier=$(printf 'sweep-n%02d' $players)

app=${BOLO_BENCH_APP:-}
if [[ -z $app ]]; then
  products=$(xcodebuild -project "$root/Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" \
    -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
  app="$products/Bolo 2026.app"
fi
binary="$app/Contents/MacOS/Bolo 2026"
if [[ ! -x $binary ]]; then
  echo "run-sweep: no app at $app (build Release first, or set BOLO_BENCH_APP)" >&2
  exit 64
fi
if [[ ! -x $swarm ]]; then
  echo "run-sweep: no swarm at $swarm (swift build -c release --product BoloBenchSwarm)" >&2
  exit 64
fi

failed=0
for ((n = first; n < first + runs; n++)); do
  number=$(printf '%02d' $n)
  id="$tier-$(date +%Y%m%dT%H%M%S)-$number"
  dest="$out/$tier/run-$number"
  rm -rf "$dest"
  mkdir -p "$dest"

  # State is not recorded: with no guest log there is nothing to compare it with, and the
  # digests would be measurement work inside the very tick being measured.
  BOLO_BENCH=1 BOLO_BENCH_STATE=0 BOLO_BENCH_FD=3 BOLO_BENCH_ROLE=host BOLO_BENCH_SCENARIO=sweep-host \
    BOLO_BENCH_PORT=$port BOLO_BENCH_RUN_ID=$id "$binary" 3> "$dest/host.jsonl" > "$dest/host.out" 2>&1 &
  host=$!
  sleep 2
  "$swarm" 127.0.0.1 $port $((players - 1)) $limit > "$dest/swarm.json" 2> "$dest/swarm.err" &
  guests=$!

  waited=0
  killed=0
  while kill -0 $host 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if ((waited >= limit)); then
      kill $host 2>/dev/null
      killed=1
      break
    fi
  done
  wait $host 2>/dev/null; hostStatus=$?
  # The swarm leaves when the host does.
  for ((i = 0; i < 10; i++)); do kill -0 $guests 2>/dev/null || break; sleep 1; done
  kill $guests 2>/dev/null
  wait $guests 2>/dev/null; swarmStatus=$?

  swarmReport=$(cat "$dest/swarm.json" 2>/dev/null)
  print -r -- "{\"runId\":\"$id\",\"scenario\":\"sweep-host\",\"tier\":\"$tier\",\"players\":$players,\"recording\":1,\"port\":$port,\"seconds\":$waited,\"killed\":$killed,\"hostExit\":$hostStatus,\"guestExit\":$swarmStatus,\"swarm\":${swarmReport:-null},\"app\":\"$app\",\"binarySHA256\":\"$(shasum -a 256 "$binary" | cut -d' ' -f1)\",\"commit\":\"$(git -C "$root" rev-parse HEAD)\",\"dirty\":$([[ -n $(git -C "$root" status --porcelain) ]] && echo true || echo false),\"powerSource\":\"$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")\"}" > "$dest/run.json"

  echo "run-$number: ${waited}s host=$hostStatus swarm=$swarmStatus killed=$killed $swarmReport"
  if ((killed || hostStatus != 0 || swarmStatus != 0)); then
    failed=$((failed + 1))
  fi
  sleep 2
done

echo "$tier: $runs run(s), $failed invalid"
exit $((failed > 0))
