#!/usr/bin/env python3
"""Owned loopback TLS tests; ephemeral private server keys stay outside Git."""
import argparse
from pathlib import Path
import json
import os
import socket
import ssl
import subprocess
import tempfile
import threading
import time
from reference_build import HERE, digest, native_source_inputs

args_parser = argparse.ArgumentParser(description=__doc__)
args_parser.add_argument('--root', type=Path, required=True)
args = args_parser.parse_args()
root = args.root.resolve()
inputs, fingerprint = native_source_inputs()
exe = root / 'native-tls-probe'
openssl = '/opt/homebrew/opt/openssl@3/bin/openssl'
subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-I/opt/homebrew/opt/openssl@3/include',
                '-I'+str(HERE.parents[1]/'Native/Client'),
                str(HERE.parents[1]/'Native/Client/CompanionNativeTLS.m'), str(HERE/'NativeTLSProbeMain.m'), '-framework', 'Foundation',
                '-L/opt/homebrew/opt/openssl@3/lib', '-lssl', '-lcrypto', '-o', str(exe)], check=True)

def command(*arguments):
    subprocess.run([openssl, *map(str, arguments)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

passed = []
with tempfile.TemporaryDirectory(prefix='native-tls-private-', dir=root) as private:
    private = Path(private); os.chmod(private, 0o700)
    prior_client = None
    for mode in ['valid', 'wrong-pin', 'unregistered', 'cancel', 'oversized', 'bad-length', 'expired-host', 'wrong-purpose']:
        directory = private / mode; directory.mkdir(mode=0o700)
        for name in ['server', 'other']:
            command('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '1', '-subj', '/CN=Disposable Native TLS Server',
                    '-addext', 'extendedKeyUsage=serverAuth', '-keyout', directory/(name+'.key'), '-out', directory/(name+'.pem'))
            command('x509', '-in', directory/(name+'.pem'), '-outform', 'DER', '-out', directory/(name+'.der'))
        listener = socket.socket(); listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(8)
        port = listener.getsockname()[1]
        if not 1025 <= port <= 65494: raise ValueError('Invalid allocated port')
        process = subprocess.Popen([str(exe), str(directory), 'invalid-pin' if mode in ['expired-host', 'wrong-purpose'] else 'valid' if mode == 'valid' else 'cancel' if mode == 'cancel' else 'reject', str(port+5), 'owned'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic()+5
            while not (directory/'client.der').exists():
                if process.poll() is not None or time.monotonic() > deadline: raise RuntimeError('Client credential preparation failed')
                time.sleep(0.005)
            command('x509', '-inform', 'DER', '-in', directory/'client.der', '-out', directory/'client.pem')
            if mode in ['expired-host', 'wrong-purpose']:
                if mode == 'expired-host':
                    command('x509', '-in', directory/'server.pem', '-signkey', directory/'server.key', '-not_before', '19990101000000Z', '-not_after', '20000101000000Z', '-outform', 'DER', '-out', directory/'expired.der')
                    data = (directory/'expired.der').read_bytes()
                else: data = (directory/'client.der').read_bytes()
                temporary = directory/'pin.tmp'; temporary.write_bytes(data); temporary.replace(directory/'host.der')
                if process.wait(timeout=5) != 0: raise RuntimeError('Invalid host pin admitted: '+mode)
                passed.append(mode); continue
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(directory/'server.pem', directory/'server.key')
            trusted = prior_client if mode == 'unregistered' else (directory/'client.pem').read_text()
            context.load_verify_locations(cadata=trusted); context.verify_mode = ssl.CERT_REQUIRED
            errors = []
            def serve():
                try:
                    connection, _ = listener.accept(); connection.settimeout(5)
                    with context.wrap_socket(connection, server_side=True) as stream:
                        if mode != 'unregistered' and stream.getpeercert(binary_form=True) != (directory/'client.der').read_bytes():
                            errors.append('Wrong TLS client identity'); return
                        request = b''
                        while b'\r\n\r\n' not in request: request += stream.recv(4096)
                        if mode == 'cancel': time.sleep(0.5); return
                        body = b'<root status_code="200"><PairStatus>1</PairStatus></root>'
                        if mode == 'oversized': body = b'x' * 1048577
                        size = len(body) + (1 if mode == 'bad-length' else 0)
                        stream.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: '+str(size).encode()+b'\r\nConnection: close\r\n\r\n'+body)
                except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
                    if mode == 'valid': errors.append('Valid TLS exchange failed')
                except Exception as error: errors.append(type(error).__name__)
            thread = threading.Thread(target=serve); thread.start()
            pin = directory / ('other.der' if mode == 'wrong-pin' else 'server.der')
            temporary = directory/'pin.tmp'; temporary.write_bytes(pin.read_bytes()); temporary.replace(directory/'host.der')
            if process.wait(timeout=10) != 0: raise RuntimeError('Native TLS admission case failed: '+mode)
            thread.join(timeout=8)
            if thread.is_alive() or errors: raise RuntimeError('TLS server assertion failed: '+mode)
            prior_client = (directory/'client.pem').read_text()
            passed.append(mode)
        finally:
            listener.close()
            if process.poll() is None: process.kill(); process.wait()
if native_source_inputs()[1] != fingerprint: raise ValueError('Sources changed during TLS tests')
report = {'profile':'maccompanion.native-tls-probe.v0.1','passed':passed,'sourceInputSHA256':fingerprint,
          'executableSHA256':digest(exe),'physicalPhone':False,'releaseAdmitted':False}
(root/'native-tls-probe-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('Native TLS probe passed:', ', '.join(passed))
