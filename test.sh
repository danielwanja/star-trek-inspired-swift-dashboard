#!/bin/sh
# Run the performance test harness. Extra arguments are passed to
# `swift test`, e.g. ./test.sh --filter "Builder toggle"
set -e
cd "$(dirname "$0")"

exec swift test "$@"
