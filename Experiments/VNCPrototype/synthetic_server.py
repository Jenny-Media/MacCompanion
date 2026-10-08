#!/usr/bin/env python3
"""Loopback-only synthetic RFB peer: no real screens, credentials, or input content.

No-auth is enabled solely in Simulator fixture mode. This is a generated
interoperability workload, not another capability-protocol golden fixture corpus.
"""
import argparse
import json
from pathlib import Path
import socket
import struct
import time

def exact(sock, count):
    result = bytearray()
    while len(result) < count:
        chunk = sock.recv(count - len(result))
        if not chunk:
            raise EOFError
        result.extend(chunk)
    return bytes(result)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--metrics', type=Path, required=True)
    args = parser.parse_args()
    stats = dict(connections=0, frameUpdates=0, framebufferResizes=0, pointerEvents=0,
                 keyDown=0, keyUp=0, heldKeys=0, buttonsReleased=True, cleanDisconnects=0,
                 fixtureDragOriginPreserved=False)
    def save():
        args.metrics.write_text(json.dumps(stats, indent=2))
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 5905)); server.listen(2)
    print('Synthetic loopback RFB peer ready', flush=True)
    while True:
        sock, _ = server.accept()
        stats['connections'] += 1; save()
        held = set()
        width, height, frames = 800, 500, 0
        try:
            sock.sendall(b'RFB 003.008\n'); assert exact(sock, 12) == b'RFB 003.008\n'
            sock.sendall(b'\x01\x01'); assert exact(sock, 1) == b'\x01'
            sock.sendall(struct.pack('>I', 0)); exact(sock, 1)
            name = b'Synthetic Desktop'
            pixel_format = struct.pack('>BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
            sock.sendall(struct.pack('>HH', width, height) + pixel_format + struct.pack('>I', len(name)) + name)
            while True:
                kind = exact(sock, 1)[0]
                if kind == 0:
                    exact(sock, 19)
                elif kind == 2:
                    header = exact(sock, 3); count = struct.unpack('>H', header[1:])[0]
                    encodings = struct.unpack('>' + 'i' * count, exact(sock, count * 4))
                    can_resize = -223 in encodings
                elif kind == 3:
                    exact(sock, 9)
                    time.sleep(0.06)
                    frames += 1
                    resize = frames in (12, 24) and can_resize
                    if resize:
                        width, height = (960, 600) if frames == 12 else (800, 500)
                        sock.sendall(b'\0\0' + struct.pack('>H', 1) + struct.pack('>HHHHi', 0, 0, width, height, -223))
                        stats['framebufferResizes'] += 1
                    else:
                        # Synthetic solid color changes every update, BGRA bytes.
                        pixels = bytes((frames % 255, 90, 180, 0)) * (width * height)
                        sock.sendall(b'\0\0' + struct.pack('>H', 1) + struct.pack('>HHHHi', 0, 0, width, height, 0) + pixels)
                        stats['frameUpdates'] += 1
                    save()
                elif kind == 4:
                    data = exact(sock, 7); down = bool(data[0]); key = struct.unpack('>I', data[3:])[0]
                    if down: held.add(key); stats['keyDown'] += 1
                    else: held.discard(key); stats['keyUp'] += 1
                    stats['heldKeys'] = len(held); save()
                elif kind == 5:
                    data = exact(sock, 5); stats['pointerEvents'] += 1
                    if data[0] == 1 and stats['buttonsReleased']:
                        x, y = struct.unpack('>HH', data[1:])
                        stats['fixtureDragOriginPreserved'] = (x, y) == (40, 50)
                    stats['buttonsReleased'] = data[0] == 0; save()
                elif kind == 6:
                    data = exact(sock, 7); count = struct.unpack('>I', data[3:])[0]
                    if count > 1024 * 1024: raise ValueError('Clipboard size limit')
                    exact(sock, count)  # Discard; never record clipboard content.
                else:
                    raise ValueError('Unexpected RFB client message type')
        except (EOFError, BrokenPipeError, ConnectionResetError):
            stats['cleanDisconnects'] += 1; save()
        finally:
            sock.close()

if __name__ == '__main__':
    main()
