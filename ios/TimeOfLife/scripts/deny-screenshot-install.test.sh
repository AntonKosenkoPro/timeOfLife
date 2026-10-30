#!/bin/sh
# Matrix test for the Screenshot install/archive guard (tasks 2.1).
#
# The guard script (`deny-screenshot-install.sh`, same directory) must deny
# install-type actions ONLY for the Screenshot configuration, while leaving
# normal builds, the test action, and ordinary Debug/Release routing
# untouched. This file also asserts the guard is wired into the app target's
# `preBuildScripts` in `project.yml` (config part of the matrix).
#
# Usage: sh ios/TimeOfLife/scripts/deny-screenshot-install.test.sh
# Exit 0 when every case behaves; nonzero otherwise (failing-first: this is
# RED while the guard script or its wiring is absent).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/scripts/deny-screenshot-install.sh"
PROJECT="$ROOT/project.yml"
FAILURES=0

check() {
    # check <description> <expected_exit> <CONFIGURATION> <ACTION>
    desc="$1"
    want="$2"
    configuration="$3"
    action="$4"
    if [ -n "$configuration" ]; then
        export CONFIGURATION="$configuration"
    else
        unset CONFIGURATION
    fi
    if [ -n "$action" ]; then
        export ACTION="$action"
    else
        unset ACTION
    fi
    if sh "$GUARD" >/dev/null 2>&1; then
        got=0
    else
        got=1
    fi
    unset CONFIGURATION ACTION
    if [ "$got" = "$want" ]; then
        echo "ok - $desc (exit $got)"
    else
        echo "NOT OK - $desc (want exit $want, got $got)"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "# guard script presence"
if [ -f "$GUARD" ]; then
    echo "ok - guard script exists"
else
    echo "NOT OK - guard script missing at $GUARD"
    FAILURES=$((FAILURES + 1))
fi

echo "# behavior matrix"
check "Screenshot+install denied" 1 "Screenshot" "install"
check "Screenshot+build allowed" 0 "Screenshot" "build"
check "Screenshot+test allowed" 0 "Screenshot" "test"
check "Screenshot+unset-action allowed" 0 "Screenshot" ""
check "Debug+install allowed" 0 "Debug" "install"
check "Release+install allowed" 0 "Release" "install"
check "unset-config+install allowed" 0 "" "install"

echo "# project.yml wiring"
if grep -q "preBuildScripts" "$PROJECT" && grep -q "deny-screenshot-install.sh" "$PROJECT"; then
    echo "ok - guard wired into preBuildScripts"
else
    echo "NOT OK - guard not wired into preBuildScripts in $PROJECT"
    FAILURES=$((FAILURES + 1))
fi

echo "# $FAILURES failure(s)"
exit "$FAILURES"
