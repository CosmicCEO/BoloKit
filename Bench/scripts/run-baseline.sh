#!/bin/zsh
# v1.6.9 baseline benchmark: the whole measurement, start to finish, on this Mac.
#
#   run-baseline.sh <phase> <name> [runs] [sweep-runs] [observer-runs]
#
#   phase           the DMAIC phase this data belongs to: measure, analyze, improve or control
#   name            where results go: Bench/data/<phase>/<name>/
#   runs            valid runs wanted per scenario            (default 10)
#   sweep-runs      runs per player count in the sweep        (default 5, 0 to skip)
#   observer-runs   runs with recording off, per scenario     (default 5, 0 to skip)
#
# Before starting: on AC power, Low Power Mode off, nothing else running, display awake, and
# leave the Mac alone until it finishes. Two game windows open and close for each run; they
# must stay fully visible, because macOS slows the timers of a window it cannot see.
#
# Takes about two hours at the defaults. Raw logs stay in Bench/runs/<phase>/<name>/ (not committed);
# the summaries, scorecards and manifest in Bench/data/<phase>/<name>/ are what gets committed.

set -u
phase=${1:?usage: run-baseline.sh <phase> <name> [runs] [sweep-runs] [observer-runs]}
name=${2:?usage: run-baseline.sh <phase> <name> [runs] [sweep-runs] [observer-runs]}
runs=${3:-10}
sweepRuns=${4:-5}
observerRuns=${5:-5}
case $phase in
  measure|analyze|improve|control) ;;
  *) echo "run-baseline: phase must be measure, analyze, improve or control" >&2; exit 64 ;;
esac

here=${0:A:h}
root=${here:h:h}
raw=$root/Bench/runs/$phase/$name
results=$root/Bench/data/$phase/$name
bench=$root/.build/release/BoloBench

if [[ -e $results/FROZEN ]]; then
  echo "run-baseline: $results is frozen. A frozen baseline is never run again; use another name." >&2
  exit 64
fi

# Conditions that must hold, checked rather than trusted.
power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
lowPower=$(pmset -g | awk '/lowpowermode/ {print $2}')
if [[ $power != "AC Power" && ${BOLO_BENCH_ANY_POWER:-0} != 1 ]]; then
  echo "run-baseline: on '$power'. Plug in, or set BOLO_BENCH_ANY_POWER=1 to run anyway." >&2
  exit 65
fi
if [[ ${lowPower:-0} != 0 ]]; then
  echo "run-baseline: Low Power Mode is on. Turn it off." >&2
  exit 65
fi

# A covered window is throttled by macOS to about 20 frames a second, which invalidates every
# run (seen 2026-09-30: a 5-minute screensaver). Declare user activity every two minutes for
# as long as this session runs; the loop ends when the session's shell does.
( while kill -0 $$ 2> /dev/null; do caffeinate -u -t 10; sleep 110; done ) > /dev/null 2>&1 &
caffeinate -d -i -w $$ > /dev/null 2>&1 &

echo "== building"
xcodebuild -project "$root/Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" -configuration Release build \
  > "$root/Bench/runs/build.log" 2>&1 || { mkdir -p "$root/Bench/runs"; echo "app build failed" >&2; exit 66; }
(cd "$root" && swift build -c release --product BoloBench > /dev/null 2>&1) || { echo "BoloBench build failed" >&2; exit 66; }
(cd "$root" && swift build -c release --product BoloBenchSwarm > /dev/null 2>&1) || { echo "BoloBenchSwarm build failed" >&2; exit 66; }
zsh "$here/check-no-wire-change.sh" > /dev/null || { echo "the wire protocol differs from v1.6.9" >&2; exit 67; }

products=$(xcodebuild -project "$root/Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" \
  -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
export BOLO_BENCH_APP="$products/Bolo 2026.app"
binary="$BOLO_BENCH_APP/Contents/MacOS/Bolo 2026"

mkdir -p "$raw" "$results"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Copies what is kept of one tier's runs (facts and summary, not the raw logs) into results.
keep() {  # raw-directory results-directory
  mkdir -p "$2"
  for run in "$1"/run-*(N/); do
    mkdir -p "$2/${run:t}"
    cp "$run/run.json" "$2/${run:t}/meta.json" 2>/dev/null
    cp "$run/summary.json" "$2/${run:t}/summary.json" 2>/dev/null
  done
  cp "$1/scorecard.json" "$2/scorecard.json" 2>/dev/null
}

echo "== pair runs: $runs per scenario, after one warm-up each"
export BOLO_BENCH_RUNS=$raw/pair
for scenario in $("$bench" scenario | awk '{print $1}'); do
  # A warm-up that fails means something is wrong with the setup, not with one run.
  if ! zsh "$here/run-pair.sh" "$scenario" 1 0 > /dev/null; then
    echo "run-baseline: the warm-up run of $scenario failed; stopping. See $raw/pair/$scenario/run-00" >&2
    exit 68
  fi
  rm -rf "$raw/pair/$scenario/run-00"
  zsh "$here/run-pair.sh" "$scenario" "$runs" 1 | tail -1
  for run in "$raw/pair/$scenario"/run-*(N/); do
    "$bench" analyze "$run" --tier pair | grep -E 'INVALID|invalid:'
  done
  "$bench" scorecard "$raw/pair/$scenario" | head -2
  keep "$raw/pair/$scenario" "$results/pair/$scenario"
done

if ((sweepRuns > 0)); then
  echo "== scaling sweep: $sweepRuns per player count, after one warm-up each"
  export BOLO_BENCH_RUNS=$raw/sweep
  for players in 2 4 8 16; do
    tier=$(printf 'sweep-n%02d' $players)
    if ! zsh "$here/run-sweep.sh" $players 1 0 > /dev/null; then
      echo "run-baseline: the warm-up run of $tier failed; stopping. See $raw/sweep/$tier/run-00" >&2
      exit 68
    fi
    rm -rf "$raw/sweep/$tier/run-00"
    zsh "$here/run-sweep.sh" $players "$sweepRuns" 1 | tail -1
    for run in "$raw/sweep/$tier"/run-*(N/); do
      "$bench" analyze "$run" --tier "$tier" | grep -E 'INVALID|invalid:'
    done
    "$bench" scorecard "$raw/sweep/$tier" | head -2
    keep "$raw/sweep/$tier" "$results/sweep/$tier"
  done
fi

if ((observerRuns > 0)); then
  echo "== observer effect: $observerRuns runs with recording off"
  mkdir -p "$results/observer"
  export BOLO_BENCH_RUNS=$raw/observer
  for scenario in s7-sustained-fire s8-soak-hidden; do
    BOLO_BENCH_RECORD=0 zsh "$here/run-pair.sh" "$scenario" "$observerRuns" 1 | tail -1
    "$bench" observer "$raw/pair/$scenario" "$raw/observer/$scenario" --out "$results/observer/$scenario.json"
  done
fi

overhead=$("$bench" overhead)
echo "$overhead"

# What this was measured on, and with what.
model=$(sysctl -n hw.model)
chip=$(sysctl -n machdep.cpu.brand_string)
memory=$(($(sysctl -n hw.memsize) / 1073741824))
displays=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Resolution/ {printf "%s%s", sep, $2; sep="; "}')
print -r -- "{
  \"name\": \"$name\",
  \"phase\": \"$phase\",
  \"started\": \"$started\",
  \"finished\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
  \"commit\": \"$(git -C "$root" rev-parse HEAD)\",
  \"describe\": \"$(git -C "$root" describe --tags --always)\",
  \"dirty\": $([[ -n $(git -C "$root" status --porcelain) ]] && echo true || echo false),
  \"base\": \"v1.6.9\",
  \"buildConfiguration\": \"Release\",
  \"binarySHA256\": \"$(shasum -a 256 "$binary" | cut -d' ' -f1)\",
  \"model\": \"$model\",
  \"chip\": \"$chip\",
  \"performanceCores\": $(sysctl -n hw.perflevel0.physicalcpu),
  \"efficiencyCores\": $(sysctl -n hw.perflevel1.physicalcpu),
  \"memoryGB\": $memory,
  \"displays\": \"$displays\",
  \"os\": \"$(sw_vers -productVersion)\",
  \"osBuild\": \"$(sw_vers -buildVersion)\",
  \"xcode\": \"$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')\",
  \"powerSource\": \"$power\",
  \"lowPowerMode\": false,
  \"network\": \"loopback (127.0.0.1), both instances on this Mac\",
  \"runsPerScenario\": $runs,
  \"sweepRunsPerPlayerCount\": $sweepRuns,
  \"observerRunsPerScenario\": $observerRuns,
  \"recorderOverhead\": \"$overhead\"
}" > "$results/manifest.json"

echo "== done: $results"
echo "Raw logs are in $raw. Nothing has been frozen or tagged."
