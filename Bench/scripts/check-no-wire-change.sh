#!/bin/zsh
# v1.6.9 baseline benchmark: proves the instrumented build speaks the same protocol as the
# tag it is measured against, and shows what it did change in shipped code.
#
#   check-no-wire-change.sh [base]      base defaults to v1.6.9
#
# Fails if any file that defines what goes over the wire differs from the base.
#
# Two modes, chosen by BOLO_WIRE_CHECK:
#   (unset)   Measure and Analyze, which add instruments and change nothing else. Fails on any
#             wire-related file and on any BoloKit file that existed at the base.
#   improve   Improve (relaxed with Jerod's approval in the Improve session): a candidate may
#             change simulation and receive-side code, but M2 -- no wire change in 1.*, decided
#             by Jerod 2026-09-29, see Bench/3-analyze/KT.md -- still holds. Fails only if
#             one of the five byte-layout files differs from the base. The files the strict mode
#             also failed on are then listed for review, not failed, so a reader sees every one.

set -u
base=${1:-v1.6.9}
here=${0:A:h}
root=${here:h:h}
cd "$root" || exit 1

mode=${BOLO_WIRE_CHECK:-strict}
case $mode in
  strict|improve) ;;
  *) echo "check-no-wire-change: BOLO_WIRE_CHECK must be unset or improve, not $mode" >&2; exit 64 ;;
esac

# The five files that fix the byte layout of every message. A change here is a wire change.
layout=(
  Sources/BoloNet/ServerMessages.swift
  Sources/BoloNet/ClientMessages.swift
  Sources/BoloNet/CLUpdateCodec.swift
  Sources/BoloNet/Preambles.swift
  Sources/BoloNet/WireIO.swift
)

# Wire-adjacent files: what is relayed, how a message is applied, the map format. Strict mode
# fails on these; improve mode lists them.
wire=(
  Sources/BoloNet/DgramServerRelay.swift
  Sources/BoloNet/DgramClientApply.swift
  Sources/BoloKit/RecvSR.swift
  Sources/BoloKit/RecvCL.swift
  Sources/BoloKit/BMap.swift
)

failed=0
echo "Mode: $mode"
for file in $layout; do
  if [[ ! -e $file ]]; then
    echo "MISSING  $file"
    failed=1
  elif ! git diff --quiet "$base" -- "$file"; then
    echo "CHANGED  $file (byte layout)"
    failed=1
  fi
done

# Wire-adjacent files: strict mode fails, improve mode only reports.
for file in $wire; do
  if [[ ! -e $file ]]; then
    echo "MISSING  $file"
    failed=1
  elif ! git diff --quiet "$base" -- "$file"; then
    if [[ $mode == improve ]]; then
      echo "REVIEW   $file (wire-adjacent; not a layout file)"
    else
      echo "CHANGED  $file"
      failed=1
    fi
  fi
done

# The simulation itself. Strict mode: nothing that existed at the base may differ. Improve mode:
# the list is the candidate's simulation footprint, printed for review.
changed=$(git diff --name-only --diff-filter=MDR "$base" -- Sources/BoloKit)
if [[ -n $changed ]]; then
  if [[ $mode == improve ]]; then
    echo "REVIEW   simulation files that existed at $base and differ (the candidate's footprint):"
    echo "$changed" | sed 's/^/           /'
  else
    echo "CHANGED  simulation files that existed at $base:"
    echo "$changed" | sed 's/^/           /'
    failed=1
  fi
fi

echo
echo "Shipped files this branch modifies (each should add recorder calls and nothing else):"
git diff --stat --diff-filter=M "$base" -- Sources 'Bolo 2026/Bolo 2026' | sed 's/^/  /'
echo
echo "Lines removed from shipped files (each should be a line re-added with a recorder call beside it):"
git diff --diff-filter=M "$base" -- Sources 'Bolo 2026/Bolo 2026' | grep -E '^-[^-]' | sed 's/^/  /'

echo
if ((failed)); then
  if [[ $mode == improve ]]; then
    echo "FAILED: a byte-layout file differs from $base; that is a wire change"
  else
    echo "FAILED: the wire protocol or the simulation differs from $base"
  fi
  exit 1
fi
if [[ $mode == improve ]]; then
  echo "OK (improve): the five byte-layout files are identical to $base; the REVIEW lines above are not failures"
  exit 0
fi
echo "OK: wire protocol and simulation are identical to $base"
