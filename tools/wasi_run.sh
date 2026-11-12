#!/usr/bin/env bash
# Runs one WASI module under wasmtime and tells a module that ran and failed from a host that could
# not run it at all.
#
#   tools/wasi_run.sh <module.wasm> <log>
#
# WHY. A battery that fails is a verdict; a wasmtime that could not start its threads is not. On a
# box near its process limit, wasmtime aborts before the module's first instruction ("failed to
# spawn thread", "Resource temporarily unavailable", a thread pool that could not be built). Read
# as a red battery, that abort would count a negative control's injection as CAUGHT when the
# battery never ran - a control that is green for the wrong reason. So such an abort is retried,
# and if the host still cannot run the module the exit status is 75 (EX_TEMPFAIL): neither green
# nor red, and every caller treats it as "did not run".
#
# The exit status is otherwise wasmtime's own, and the log holds the run that decided it.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
wasm="$1"; log="$2"
HOST_REFUSED='failed to spawn thread|Resource temporarily unavailable|ThreadPoolBuildError|fork: retry'
for attempt in 1 2 3 4 5 6; do
  wasmtime "$wasm" > "$log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && exit 0
  grep -Eq "$HOST_REFUSED" "$log" || exit "$rc"
  sleep $((attempt * 5))
done
echo "wasi_run: the host could not run $wasm after 6 attempts" >> "$log"
exit 75
