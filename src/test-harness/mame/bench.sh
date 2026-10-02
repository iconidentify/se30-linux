#!/bin/sh
# Boot an image in MAME's SE/30 (Penguin auto-boots Linux) and run se30bench.
# usage: bench.sh <image> <label> [-x]
B=$(dirname "$(readlink -f "$0")"); W=$B/mame
IMG=$1 LABEL=$2 XFLAG=${3:--x}
mkdir -p $B/results
sudo docker run --rm -v $B:/build -w /build -e PATH=/usr/games:/usr/bin:/bin se30-mame \
    chdman createhd -i "$IMG" -o /build/mame/card.chd -c none -f >/dev/null 2>&1 || exit 1
sudo rm -f $W/serial.log
$W/run.sh; sleep 3
log() { sudo cat $W/serial.log 2>/dev/null | tr -d '\r'; }
i=0
until log | grep -q 'login:'; do
    MC_TIMEOUT=600 $W/mc 'wait 30' >/dev/null; i=$((i + 1))
    [ $i -gt 60 ] && { echo "bench: no login prompt"; exit 1; }
done
$W/ser 'root' 20 >/dev/null
$W/ser "se30bench $XFLAG" 5 >/dev/null
i=0
until log | grep -q 'BENCH done'; do
    MC_TIMEOUT=600 $W/mc 'wait 30' >/dev/null; i=$((i + 1))
    [ $i -gt 120 ] && { echo "bench: timed out"; break; }
done
log | grep '^BENCH' | grep -v done | awk '{print $2, $3}' > $B/results/$LABEL.txt
printf 'quit\n' > $W/ctl/cmd
for i in $(seq 1 30); do sudo docker ps -q --filter name=se30mame | grep -q . || break; sleep 1; done
cat $B/results/$LABEL.txt
