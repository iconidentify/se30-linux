#!/bin/sh
# (Re)start the emulated SE/30 in the background.
W=$(dirname "$(readlink -f "$0")")
sudo docker rm -f se30mame >/dev/null 2>&1
sudo rm -f "$W"/ctl/*
sudo touch "$W/serial.log"
sudo docker run -d --name se30mame -v "$W":/work -w /work -e PATH=/usr/games:/usr/bin:/bin -e XDG_RUNTIME_DIR=/tmp se30-mame sh -c "
python3 /work/serialbridge.py & sleep 1; xvfb-run -a mame macse30 -rompath /work/roms -ramsize 64M -hard card.chd -modem null_modem -bitb socket.127.0.0.1:2323 \
  -video none -sound none -nothrottle -skip_gameinfo -nvram_directory /work/nvram2 -cfg_directory /work/cfg2 \
  -snapshot_directory /work/shots -autoboot_script /work/remote.lua > /work/mame.log 2>&1" >/dev/null
