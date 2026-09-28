#!/bin/zsh
# v1.6.9 baseline benchmark: proves the instrumented build speaks the same protocol as the
# tag it is measured against, and shows what it did change in shipped code.
#
#   check-no-wire-change.sh [base]      base defaults to v1.6.9
#
# Fails if any file that defines what goes over the wire differs from the base.

set -u
base=${1:-v1.6.9}
here=${0:A:h}
root=${here:h:h}
cd "$root" || exit 1

wire=(
  Sources/BoloNet/ServerMessages.swift
  Sources/BoloNet/ClientMessages.swift
  Sources/BoloNet/CLUpdateCodec.swift
  Sources/BoloNet/Preambles.swift
  Sources/BoloNet/WireIO.swift
  Sources/BoloNet/DgramServerRelay.swift
  Sources/BoloNet/DgramClientApply.swift
  Sources/BoloKit/RecvSR.swift
  Sources/BoloKit/RecvCL.swift
  Sources/BoloKit/BMap.swift
)

failed=0
for file in $wire; do
  if [[ ! -e $file ]]; then
    echo "MISSING  $file"
    failed=1
  elif ! git diff --quiet "$base" -- "$file"; then
    echo "CHANGED  $file"
    failed=1
  fi
done

# The simulation itself: nothing that existed at the base may differ.
changed=$(git diff --name-only --diff-filter=MDR "$base" -- Sources/BoloKit)
if [[ -n $changed ]]; then
  echo "CHANGED  simulation files that existed at $base:"
  echo "$changed" | sed 's/^/           /'
  failed=1
fi

echo
echo "Shipped files this branch modifies (each should add recorder calls and nothing else):"
git diff --stat --diff-filter=M "$base" -- Sources 'Bolo 2026/Bolo 2026' | sed 's/^/  /'
echo
echo "Lines removed from shipped files (each should be a line re-added with a recorder call beside it):"
git diff --diff-filter=M "$base" -- Sources 'Bolo 2026/Bolo 2026' | grep -E '^-[^-]' | sed 's/^/  /'

echo
if ((failed)); then
  echo "FAILED: the wire protocol or the simulation differs from $base"
  exit 1
fi
echo "OK: wire protocol and simulation are identical to $base"
