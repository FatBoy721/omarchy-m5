#!/usr/bin/env python3
# msh.py 'cmd' [timeout]: run a shell command on the Mac over /dev/ttyUSB0, print its output
import os, sys, time, re, uuid, termios
cmd = sys.argv[1]; to = float(sys.argv[2]) if len(sys.argv) > 2 else 30
import socket; s = socket.create_connection(('127.0.0.1', 7777)); s.setblocking(False); fd = s.fileno()
tag = uuid.uuid4().hex[:8]
while True:  # drain
    try:
        if not s.recv(65536): break
    except BlockingIOError: break
s.sendall(f"export SYSTEMD_PAGER=cat PAGER=cat SYSTEMD_COLORS=0 TERM=dumb; stty -echo 2>/dev/null; echo B{tag}; {{ {cmd} ; }} 2>&1; echo E{tag} $?\n".encode())
buf = b''; end = time.time() + to
while time.time() < end:
    try: buf += s.recv(65536)
    except BlockingIOError: time.sleep(0.05)
    if f"E{tag}".encode() in buf.split(f"B{tag}".encode(), 1)[-1]: break
s = buf.decode(errors='replace'); s = re.sub(r'\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[a-zA-Z]|\r', '', s)
body = s.split(f"B{tag}\n", 1)[-1] if f"B{tag}\n" in s else s
print(body.split(f"E{tag}")[0].rstrip()); m = re.search(f"E{tag} (\\d+)", s); sys.exit(int(m.group(1)) if m else 124)
