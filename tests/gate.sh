#!/bin/sh
# The one definition of "green" for a Campground plugin. The agent runs it before every push, and CI runs the same
# file, so the desk and the pipeline can't disagree about what passing means.
#
#   sh tests/gate.sh                     every step
#   JELLYFIN_VERSION=12.4.0 sh tests/gate.sh   build and test against another Jellyfin package (CI's matrix)
#   JELLYFIN_TFM=net10.0 ...              also narrow a multi-targeting plugin to one framework
#
# Every step runs even after a failure, and the summary names each, so one red step doesn't hide another.
# Plugin settings live in tests/gate.conf (sourced): PROJECT, TEST_PROJECTS, and an optional gate_extra function for
# plugin-specific steps (translations, a binary check, a JS harness runner...). Counts are printed, never written
# into documents.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 2

PROJECT=
TEST_PROJECTS=
[ -f tests/gate.conf ] || { echo "gate: tests/gate.conf is missing (see methodology/README.md)" >&2; exit 2; }
. ./tests/gate.conf
[ -n "$PROJECT" ] || { echo "gate: PROJECT is not set in tests/gate.conf" >&2; exit 2; }

jf=
[ -n "${JELLYFIN_VERSION:-}" ] && jf="-p:JellyfinVersion=$JELLYFIN_VERSION"
# A plugin that multi-targets (Bonfire: net9.0 for 10.11, net10.0 for 12.x) must also narrow the frameworks, or a
# 12.x package is restored for net9.0 and fails with NU1202 (GameTent's shared-ci hit exactly this).
# `-f` doesn't help: restore still covers every framework.
[ -n "${JELLYFIN_TFM:-}" ] && jf="$jf -p:TargetFrameworks=$JELLYFIN_TFM"

fail=0; steps=0; failed=
step() {
    name=$1; shift
    steps=$((steps + 1))
    echo "=== $name: $*"
    if "$@"; then echo "=== PASS $name"; else echo "=== FAIL $name"; fail=1; failed="$failed $name"; fi
}

echo "gate: $(git rev-parse --short HEAD 2>/dev/null) on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)${JELLYFIN_VERSION:+, Jellyfin $JELLYFIN_VERSION}"

# A warning is a failure, and --no-incremental means a stale build can't pass for a fresh one.
step build dotnet build "$PROJECT" -c Release -warnaserror --no-incremental -nologo -v q $jf

for t in $TEST_PROJECTS; do
    step "test:$(basename "$t")" dotnet test "$t" -c Release -nologo -v q $jf
done

if [ -f Campground.Shared/check-shared.sh ]; then
    step shared-copy sh Campground.Shared/check-shared.sh
fi

[ -f tools/check-kit.sh ] && step kit-copy sh tools/check-kit.sh
step public-guard sh tools/guard-public.sh --tree

if command -v gate_extra >/dev/null 2>&1; then
    gate_extra
fi

if [ $fail -eq 0 ]; then
    echo "=== GATE PASS ($steps steps)"
else
    echo "=== GATE FAIL ($steps steps; failed:$failed)"
fi
exit $fail
