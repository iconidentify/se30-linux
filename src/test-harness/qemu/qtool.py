#!/usr/bin/env python3
# Drive the QEMU test: serial console, telnet and monitor over sockets.
#   qtool.py serial "cmd" [wait]    run a command on the serial login shell
#   qtool.py login                  log in as root on the serial port
#   qtool.py telnet "cmd" [wait]    log in over telnet (127.0.0.1:2323) and run cmd
#   qtool.py mon "monitor cmd"      QEMU monitor command
import socket, sys, time

def drain(s, wait):
    s.settimeout(0.3); out = b""; end = time.time() + wait
    while time.time() < end:
        try:
            d = s.recv(4096)
            if not d: break
            out += d
        except socket.timeout:
            pass
    return out

def strip_iac(b):
    out = bytearray(); i = 0
    while i < len(b):
        if b[i] == 255 and i + 2 < len(b):
            i += 3; continue
        out.append(b[i]); i += 1
    return bytes(out)

def unix(path):
    s = socket.socket(socket.AF_UNIX); s.connect(path); return s

op = sys.argv[1]
if op in ("serial", "login"):
    s = unix("/q/ser.sock")
    drain(s, 0.5)
    if op == "login":
        s.send(b"\r"); out = drain(s, 3)
        if b"login:" in out:
            s.send(b"root\r"); out += drain(s, 8)
    else:
        s.send(sys.argv[2].encode() + b"\r"); out = drain(s, float(sys.argv[3]) if len(sys.argv) > 3 else 5)
    sys.stdout.write(out.decode(errors="replace").replace("\r", ""))
elif op == "telnet":
    s = socket.create_connection(("127.0.0.1", 2323), timeout=10)
    out = strip_iac(drain(s, 6))
    s.send(b"root\r\n"); out += strip_iac(drain(s, 6))
    s.send(sys.argv[2].encode() + b"\r\n"); out += strip_iac(drain(s, float(sys.argv[3]) if len(sys.argv) > 3 else 6))
    sys.stdout.write(out.decode(errors="replace").replace("\r", ""))
elif op == "mon":
    s = unix("/q/mon.sock"); drain(s, 0.5)
    s.send(sys.argv[2].encode() + b"\n"); sys.stdout.write(drain(s, 1.5).decode(errors="replace"))
