#!/bin/sh
# Run bench.sh for each "image:label[:flag]" in turn (one MAME at a time).
cd "$(dirname "$(readlink -f "$0")")"
for spec in "$@"; do
    img=${spec%%:*}; rest=${spec#*:}; label=${rest%%:*}; flag=-x
    [ "$rest" != "$label" ] && flag=${rest#*:}
    ./bench.sh "$img" "$label" "$flag" > "bench-$label.log" 2>&1
done
