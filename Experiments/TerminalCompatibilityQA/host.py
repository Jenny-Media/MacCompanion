"""Loopback SSH -> disposable real-tool PTYs. No user account or raw I/O logs."""
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import secrets
import select
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

import paramiko
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat


class Session(paramiko.ServerInterface):
    def __init__(self, host):
        self.host = host
        self.tool = None
        self.shell = threading.Event()
        self.master = None
        self.grid = (80, 24)

    def get_allowed_auths(self, username):
        return 'password'

    def check_auth_password(self, username, password):
        if username in self.host.tools and secrets.compare_digest(password, self.host.token):
            self.tool = username
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' and chanid == 0 else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_pty_request(self, channel, term, width, height, pixelwidth, pixelheight, modes):
        if term != b'xterm-256color' or not (1 <= width <= 500 and 1 <= height <= 500):
            return False
        self.grid = (width, height)
        return True

    def check_channel_shell_request(self, channel):
        self.shell.set()
        return True

    def check_channel_window_change_request(self, channel, width, height, pixelwidth, pixelheight):
        if not (1 <= width <= 500 and 1 <= height <= 500):
            return False
        self.grid = (width, height)
        if self.master is not None:
            self.resize()
        return True

    def resize(self):
        cols, rows = self.grid
        try:
            fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        except OSError:
            pass  # A concurrent disconnect can already have closed this exact PTY.


class ToolHost:
    def __init__(self, output, tools):
        self.output = Path(output)
        self.root = Path(tempfile.mkdtemp(prefix='mcqa-tools-', dir='/private/tmp'))
        # The PTY and cleanup commands run from the disposable host root.
        # Resolve caller-relative paths before changing the child's directory.
        self.tools = {name: Path(path).expanduser().resolve() for name, path in tools.items()}
        self.token = secrets.token_urlsafe(32)
        material = Ed25519PrivateKey.generate().private_bytes(Encoding.PEM, PrivateFormat.OpenSSH, NoEncryption())
        self.key = paramiko.Ed25519Key(file_obj=io.StringIO(material.decode()))
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(8)
        self.listener.settimeout(0.2)
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.transports = []
        self.threads = []
        self.children = set()
        self.started = set()
        self.errors = []
        self.versions = {name: subprocess.check_output([str(path), '-V' if name == 'tmux' else '--version'], text=True, timeout=5).strip() for name, path in self.tools.items()}
        self.binary_hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in self.tools.items()}
        self.names = {name: 'mcqa-' + secrets.token_hex(4) for name in self.tools}
        self.environment = dict(os.environ)
        for name in ['TMUX', 'TMUX_PANE', 'ZELLIJ', 'ZELLIJ_SESSION_NAME', 'SSH_AUTH_SOCK', 'ENV', 'BASH_ENV', 'PROMPT_COMMAND']:
            self.environment.pop(name, None)
        self.environment.update(TERM='xterm-256color', LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8', SHELL='/bin/sh',
                                HISTFILE=os.devnull, HISTSIZE='0', HISTFILESIZE='0')
        self.environment['HERDR_CONFIG_PATH'] = str(self.root / 'herdr.toml')
        self.environment['HERDR_DISABLE_SOUND'] = '1'
        for name in ['XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR']:
            path = self.root / name.lower()
            path.mkdir(mode=0o700)
            self.environment[name] = str(path)
        self.shell = self.root / 'pane-shell'
        self.shell.write_text("#!/bin/sh\nPS1='MCQA> '\nexport PS1\nexec /bin/bash --noprofile --norc -i\n")
        self.shell.chmod(0o700)
        (self.root / 'zellij.kdl').write_text('default_shell "' + str(self.shell) + '"\nsimplified_ui true\npane_frames false\nsession_serialization false\nshow_startup_tips false\nshow_release_notes false\n')
        (self.root / 'layout.kdl').write_text('layout {\n    pane\n}\n')
        (self.root / 'herdr.toml').write_text('onboarding = false\n[terminal]\ndefault_shell = "' + str(self.shell) + '"\nshell_mode = "non_login"\n')

    def __enter__(self):
        self.output.mkdir(parents=True, exist_ok=True)
        self.descriptor_path = self.output / 'tool-host.json'
        descriptor = {'port': self.listener.getsockname()[1], 'password': self.token,
                      'hostKey': self.key.get_name() + ' ' + self.key.get_base64(), 'tools': self.versions}
        fd = os.open(self.descriptor_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(descriptor, stream)
        self.acceptor = threading.Thread(target=self.accept, daemon=True)
        self.acceptor.start()
        return self

    def accept(self):
        while not self.stop.is_set():
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            thread = threading.Thread(target=self.bridge, args=(connection,), daemon=True)
            with self.lock:
                self.threads.append(thread)
            thread.start()

    def argv(self, tool):
        path, name = str(self.tools[tool]), self.names[tool]
        if tool == 'tmux':
            return [path, '-S', str(self.root / 'tmux.sock'), '-f', '/dev/null', 'new-session', '-A', '-s', name, str(self.shell)]
        if tool == 'zellij':
            return [path, '--config', str(self.root / 'zellij.kdl'), '--data-dir', str(self.root / 'data'),
                    '--layout', str(self.root / 'layout.kdl'), 'attach', '--create', name]
        return [path, '--session', name]

    def bridge(self, connection):
        transport, master, process = None, None, None
        try:
            transport = paramiko.Transport(connection)
            with self.lock:
                self.transports.append(transport)
            transport.add_server_key(self.key)
            session = Session(self)
            transport.start_server(server=session)
            channel = transport.accept(15)
            if channel is None:
                return
            deadline = time.monotonic() + 15
            while not session.shell.wait(0.1) and not self.stop.is_set() and time.monotonic() < deadline:
                pass
            if not session.shell.is_set() or self.stop.is_set():
                return
            channel.settimeout(5)
            master, slave = pty.openpty()
            try:
                session.master = master; session.resize()
                process = subprocess.Popen([sys.executable, str(Path(__file__).with_name('pty_child.py')), *self.argv(session.tool)],
                    stdin=slave, stdout=slave, stderr=slave, cwd=self.root, env=self.environment, start_new_session=True)
            finally:
                os.close(slave)
            with self.lock:
                self.children.add(process); self.started.add(session.tool)
            while not self.stop.is_set() and transport.is_active() and not channel.closed:
                ready, _, _ = select.select([master, channel], [], [], 0.1)
                if channel in ready:
                    data = channel.recv(65536)
                    if not data:
                        break
                    view = memoryview(data)
                    while view:
                        view = view[os.write(master, view):]
                if master in ready:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    channel.sendall(data)
                if process.poll() is not None:
                    break
        except (EOFError, OSError, paramiko.SSHException) as error:
            if not self.stop.is_set():
                with self.lock:
                    self.errors.append(type(error).__name__)
        finally:
            if transport is not None:
                transport.close()
            connection.close()
            if master is not None:
                os.close(master)
            if process is not None:
                self.retire(process)
                with self.lock:
                    self.children.discard(process)

    @staticmethod
    def retire(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=3)

    def __exit__(self, *exc):
        cleanup = {}
        cleanup_errors = {}
        teardown_errors = []
        threads = []
        self.stop.set()
        try:
            try:
                self.listener.close()
            except OSError as error:
                teardown_errors.append(type(error).__name__)
            self.acceptor.join(timeout=2)
            with self.lock:
                transports, children, threads = list(self.transports), list(self.children), list(self.threads)
            for transport in transports:
                try:
                    transport.close()
                except OSError as error:
                    teardown_errors.append(type(error).__name__)
            for process in children:
                try:
                    self.retire(process)
                except (OSError, subprocess.TimeoutExpired) as error:
                    teardown_errors.append(type(error).__name__)
            for thread in threads:
                thread.join(timeout=5)
            with self.lock:
                started = sorted(self.started)
            for tool in started:
                if tool == 'tmux':
                    command = [str(self.tools[tool]), '-S', str(self.root / 'tmux.sock'), 'kill-server']
                elif tool == 'zellij':
                    command = [str(self.tools[tool]), 'kill-session', self.names[tool]]
                else:
                    command = [str(self.tools[tool]), 'session', 'stop', self.names[tool]]
                # A failed stop must not prevent cleanup of the other sessions.
                cleanup[tool] = None
                try:
                    result = subprocess.run(command, env=self.environment, cwd=self.root, capture_output=True, timeout=10)
                    cleanup[tool] = result.returncode
                except (OSError, subprocess.TimeoutExpired) as error:
                    cleanup_errors[tool] = type(error).__name__
        finally:
            with self.lock:
                remaining = sum(p.poll() is None for p in self.children)
            descriptor_retired = False
            try:
                self.descriptor_path.unlink(missing_ok=True)  # Retire the generated test password.
                descriptor_retired = True
            except OSError as error:
                teardown_errors.append(type(error).__name__)
            (self.output / 'tool-host-report.json').write_text(json.dumps({
                'versions': self.versions, 'binarySHA256': self.binary_hashes, 'loopbackOnly': True, 'rawInputOutputRecorded': False,
                'testRoot': str(self.root), 'cleanupExitCodes': cleanup, 'cleanupErrorTypes': cleanup_errors,
                'teardownErrorTypes': teardown_errors, 'descriptorRetired': descriptor_retired,
                'remainingClientProcesses': remaining,
                'remainingBridgeThreads': sum(t.is_alive() for t in threads), 'transportErrorTypes': self.errors,
            }, indent=2) + '\n')
