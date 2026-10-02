#!/bin/sh
# Wait for the running benchmark queue, then run more: queue.sh img:label ...
cd "$(dirname "$(readlink -f "$0")")"
while pgrep -f "runbench.sh" >/dev/null; do sleep 20; done
exec ./runbench.sh "$@"
