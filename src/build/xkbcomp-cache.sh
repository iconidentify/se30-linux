#!/bin/sh
# xkbcomp wrapper: X compiles its keymap with xkbcomp at every start, which
# takes minutes on a 68030. Reuse the compiled keymap while the input (the
# keymap description on stdin plus the options) is unchanged.
# The real compiler is /usr/bin/xkbcomp.real.
for a; do out=$a; done                  # last argument: output file
in=$(mktemp) || exit 1
cat > "$in"
key=$( { cat "$in"; printf '%s\n' "$@" | sed '$d'; } | md5sum | cut -c1-32)
cache=/var/cache/xkbcomp/$key.xkm
if [ -s "$cache" ]; then
    cp "$cache" "$out"
    rc=$?
else
    /usr/bin/xkbcomp.real "$@" < "$in"
    rc=$?
    [ $rc = 0 ] && [ -s "$out" ] && mkdir -p /var/cache/xkbcomp && cp "$out" "$cache"
fi
rm -f "$in"
exit $rc
