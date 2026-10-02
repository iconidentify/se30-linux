#!/bin/sh
# Runs in se30-build (privileged): Debian sid m68k roots from debian-ports.
# $1 = output dir, $2 = extra packages
set -e
OUT=$1; shift
rm -rf "$OUT"
mmdebstrap --architectures=m68k --variant=minbase \
  --keyring=/usr/share/keyrings/debian-ports-archive-keyring.gpg \
  --include="$*" \
  --aptopt='Acquire::Retries "5"' \
  --dpkgopt='path-exclude=/usr/share/doc/*' --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --dpkgopt='path-exclude=/usr/share/man/*' --dpkgopt='path-exclude=/usr/share/locale/*' \
  sid "$OUT" http://ftp.ports.debian.org/debian-ports
du -sh "$OUT"
