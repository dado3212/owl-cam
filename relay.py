#!/usr/bin/env python3
"""
Usage:
    python3 relay.py

Endpoints:
    /stream  — MJPEG proxy
    /status  — JSON: {"live": true/false, "clients": N}
"""

import argparse
import threading
import time
import urllib.request
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

latest_frame = None
frame_lock = threading.Lock()
source_connected = False
client_count = 0
client_lock = threading.Lock()
frame_event = threading.Event()
source_connected_since = None

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == '/stream':
            self.handle_stream()
        elif self.path == '/status':
            self.handle_status()
        else:
            self.send_error(404)

    def handle_status(self):
        global client_count, source_connected, source_connected_since
        with client_lock:
            cc = client_count
        uptime = int(time.time() - source_connected_since) if source_connected_since else 0
        body = '{{"live":{},"clients":{},"uptime":{}}}'.format(
            'true' if source_connected else 'false', cc, uptime
        ).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def handle_stream(self):
        global client_count
        if not source_connected:
            self.send_error(503)
            return

        self.send_response(200)
        self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=--owlframe')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()

        with client_lock:
            client_count += 1

        try:
            while True:
                frame_event.wait(timeout=5.0)

                with frame_lock:
                    frame = latest_frame

                if frame is None:
                    if not source_connected:
                        break
                    continue

                try:
                    self.wfile.write(
                        b'--owlframe\r\n'
                        b'Content-Type: image/jpeg\r\n'
                        b'Content-Length: ' + str(len(frame)).encode() + b'\r\n'
                        b'\r\n'
                    )
                    self.wfile.write(frame)
                    self.wfile.write(b'\r\n')
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break

                time.sleep(0.08)
        finally:
            with client_lock:
                client_count -= 1


def pull_source():
    global latest_frame, source_connected, source_connected_since

    while True:
        try:
            resp = urllib.request.urlopen('http://76.102.101.255:16146/stream', timeout=30)
            source_connected = True
            source_connected_since = time.time()

            buf = b''
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    break
                buf += chunk

                while b'--owlframe' in buf:
                    header_end = buf.find(b'\r\n\r\n')
                    if header_end == -1:
                        break

                    content_length = None
                    for line in buf[:header_end].decode('utf-8', errors='ignore').split('\r\n'):
                        if line.lower().startswith('content-length:'):
                            content_length = int(line.split(':')[1].strip())
                            break

                    if content_length is None:
                        nxt = buf.find(b'--owlframe', header_end + 4)
                        if nxt == -1:
                            break
                        buf = buf[nxt:]
                        continue

                    data_start = header_end + 4
                    data_end = data_start + content_length

                    if len(buf) < data_end:
                        break

                    with frame_lock:
                        latest_frame = buf[data_start:data_end]

                    frame_event.set()
                    frame_event.clear()

                    buf = buf[data_end:]
                    if buf.startswith(b'\r\n'):
                        buf = buf[2:]

        except Exception as e:
            print(f'[relay] Source error: {e}')

        source_connected = False
        source_connected_since = None
        time.sleep(5)

threading.Thread(target=pull_source, daemon=True).start()

print(f'[relay] Listening on :16146')
ThreadingHTTPServer(('127.0.0.1', 16146), Handler).serve_forever()

