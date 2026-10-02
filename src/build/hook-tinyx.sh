#!/bin/sh
# Add TinyX (Xfbdev, native 1 bpp) and startx-tiny to a root filesystem.
R=$1
touch $R/etc/noxserver      # no Xvfb at boot: TinyX needs display :0
install -m 755 /build/Xfbdev $R/usr/local/bin/Xfbdev
install -m 755 /build/rxvt $R/usr/local/bin/rxvt
cat > $R/usr/local/bin/startx-tiny <<'EOS'
#!/bin/sh
# startx-tiny: X on the Mac screen with TinyX (Xfbdev), twm and an xterm.
export DISPLAY=:0
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
Xfbdev :0 -nolisten tcp >/var/log/Xfbdev.log 2>&1 &
XPID=$!
until [ -S /tmp/.X11-unix/X0 ]; do
    kill -0 $XPID 2>/dev/null || { echo "startx-tiny: X died, see /var/log/Xfbdev.log"; exit 1; }
    sleep 1
done
trap 'kill $XPID 2>/dev/null' EXIT INT TERM
xsetroot -grey
${TERMINAL:-rxvt} -geometry 80x24+4+24 -T SE/30 -ls &
twm
EOS
chmod 755 $R/usr/local/bin/startx-tiny
