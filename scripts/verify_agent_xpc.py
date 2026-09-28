#!/usr/bin/env python3
"""Opt-in, signed, disposable multi-process Agent startup/XPC integration lane.

Never bootouts/restarts a production label. Never writes Keychain/TCC. Reports
pass only after all exact assertions and cleanup; no timeout counts as rejection.
"""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CASES = {
    "firstUnlock", "preparationFailure", "invalidRevision", "no-service-rejected",
    "disabled-denies-readiness", "durable-enable-receipt", "disabled-concurrent-finish",
    "listener-failure-no-fallback", "restart-loads-enabled-intent", "enabled-denies-bootstrap",
    "status-before-ready", "duplicate-ready", "same-instance-reconnect", "wrong-menu-identity",
    "malformed-hello-version", "malformed-hello-extra", "adhoc-peer-rejected-by-server",
    "new-menu-retires-old-generation", "enabled-concurrent-finish", "wrong-agent-identity",
    "unavailable-status-without-disconnect", "status-timeout-drops-late-reply",
    "agent-death-during-pending-read", "recovery-after-agent-death",
    "primary-production-status", "primary-production-denies-bootstrap",
    "primary-production-reconnect", "primary-production-peer-retirement",
    "primary-production-concurrent-finish", "primary-production-restart-identity",
    "primary-production-abrupt-restart", "primary-production-missing-key-fails-closed",
    "production-menu-presentation-and-pairing", "production-menu-concurrent-finish",
    "production-loopback-binding",
    "production-real-client-pairing", "production-real-client-reconnect",
    "production-menu-loss-outstanding-qr", "production-real-client-agent-restart",
    "production-real-client-agent-crash-restart",
    "production-signed-control-grant-and-runtime",
    "production-final-admission-race", "production-menu-loss-retires-control",
    "production-unconfirmed-revocation-review", "production-signed-active-device-revocation",
    "production-revoked-client-reconnect", "production-revocation-agent-restart",
    "production-revocation-agent-crash-restart",
    "production-revocation-during-preparation",
    "production-signed-act-grant-and-operations", "production-act-agent-restart-replay",
    "production-act-agent-crash-restart-replay",
    "production-act-remote-ungranted-denial",
    "production-act-same-primary-cancellation", "production-act-inflight-crash-recovery",
}


def source_fingerprint():
    """Bind evidence to local source, including a dirty worktree, without secrets."""
    paths = [Path(__file__), ROOT / "Experiments/LiveControlLab/Package.swift",
             ROOT / "Packages/MacCompanionKit/Package.swift"]
    for directory in ("Packages/MacCompanionKit/Sources",
                      "Experiments/LiveControlLab/Sources/AgentXPCTest",
                      "Experiments/LiveControlLab/Sources/AgentXPCRawProbe"):
        paths.extend(path for path in (ROOT / directory).rglob("*") if path.suffix in {".swift", ".c", ".h"})
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


class Probe:
    def __init__(self):
        self.package_path = ROOT / "Experiments/LiveControlLab"
        self.started = time.time()
        self.source_sha256 = source_fingerprint()
        self.test_id = str(uuid.uuid4())
        self.label = f"media.jenny.maccompanion.xpc-test.{self.test_id}"
        self.domain = f"gui/{os.getuid()}"
        self.job = f"{self.domain}/{self.label}"
        self.state = Path(f"/private/tmp/maccompanion-agent-xpc-{self.test_id}")
        self.state.mkdir(mode=0o700)  # fail on collision; never adopt another run
        self.evidence = Path(tempfile.mkdtemp(prefix="maccompanion-agent-xpc-evidence.", dir="/private/tmp"))
        self.loaded = False
        self.children = []
        self.agent_pids = []
        self.cases = []
        self.serial = 0
        self.server_log = None
        self.last_plist = None

    def command(self, args, *, timeout=25, name="command"):
        self.serial += 1
        log = self.evidence / f"{self.serial:02d}-{name}.log"
        with log.open("w") as output:
            result = subprocess.run([str(x) for x in args], cwd=ROOT, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            raise RuntimeError(f"{name} failed ({result.returncode}); see {log}")
        return log.read_text()

    def case(self, name, action):
        start = time.monotonic()
        action()
        self.cases.append({"name": name, "status": "passed", "seconds": round(time.monotonic() - start, 3)})
        print(f"PASS {name}", flush=True)

    @staticmethod
    def contains(text, marker):
        if marker not in text.splitlines():
            raise AssertionError(f"Missing exact marker: {marker}")

    def client(self, mode, *, binary="menu", role="client", marker=None):
        text = self.command([self.evidence / binary, role, self.test_id, mode], name=f"{binary}-{mode}")
        if marker:
            self.contains(text, marker)

    def wait_marker(self, log, marker, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if log.exists() and marker in log.read_text().splitlines():
                return
            time.sleep(0.05)
        raise AssertionError(f"No {marker} in {log}")

    def start_server(self, mode="normal", binary="agent"):
        if self.loaded:
            raise AssertionError("A disposable job is already loaded")
        self.server_log = self.evidence / f"server-{self.serial}-{mode}-{binary}.log"
        plist = self.evidence / "disposable.plist"
        plist.write_bytes(plistlib.dumps({
            "Label": self.label,
            "ProgramArguments": [str(self.evidence / binary), "server", self.test_id, mode],
            "MachServices": {self.label: True},
            "RunAtLoad": True, "ProcessType": "Background",
            "StandardOutPath": str(self.server_log), "StandardErrorPath": str(self.server_log),
        }))
        self.last_plist = plist
        self.loaded = True
        self.command(["launchctl", "bootstrap", self.domain, plist], name="bootstrap-job")
        self.capture_job_state("after-bootstrap")
        try:
            # Production enabled startup waits for an authenticated menu before
            # the listener starts; connect only after real local XPC activation.
            marker = "local-xpc-listening" if mode in {"productionPresentation", "productionPaired", "productionInteractive", "productionActPaused"} else "service-running"
            self.wait_marker(self.server_log, marker)
        except Exception:
            if self.capture_job_state("startup-failed"):
                # Read-only stack sample of this exact disposable process;
                # never sample the user's installed Agent or other apps.
                subprocess.run(["sample", str(self.agent_pids[-1]), "1", "10", "-file",
                                str(self.evidence / "startup-failed.sample.txt")],
                               capture_output=True, timeout=8)
            raise
        if not self.capture_job_state("service-ready"):
            raise AssertionError("Disposable Agent PID not found")

    def capture_job_state(self, reason):
        """Keep exact-job launch evidence and track PID even before readiness."""
        self.serial += 1
        result = subprocess.run(["launchctl", "print", self.job], capture_output=True, text=True, timeout=5)
        pid = re.search(r"^\s*pid = (\d+)$", result.stdout, re.MULTILINE)
        if pid:
            value = int(pid.group(1))
            if value not in self.agent_pids:
                self.agent_pids.append(value)
        (self.evidence / f"{self.serial:02d}-job-{reason}.log").write_text(result.stdout + result.stderr)
        return pid is not None

    def wait_agent_exit(self):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            live = []
            for pid in self.agent_pids:
                try:
                    os.kill(pid, 0)
                    live.append(pid)
                except ProcessLookupError:
                    pass
            self.agent_pids = live
            if not live:
                return
            time.sleep(.05)
        raise RuntimeError("Disposable Agent process did not exit")

    def stop_server(self, *, abrupt=False):
        if not self.loaded:
            return
        self.command(["launchctl", "kill", "SIGKILL" if abrupt else "SIGTERM", self.job], name="stop-job")
        if not abrupt:
            self.wait_marker(self.server_log, "service-finished")
            assert self.server_log.read_text().splitlines().count("prepared-finished") == 1
        self.command(["launchctl", "bootout", self.job], name="bootout-job")
        self.loaded = False
        self.wait_agent_exit()
        result = subprocess.run(["launchctl", "print", self.job], capture_output=True, timeout=5)
        if result.returncode == 0:
            raise AssertionError("Disposable job survived bootout")

    def background_client(self, mode, *, log_suffix=None, environment=None):
        name = f"background-{self.serial}-{mode}"
        log = self.evidence / f"{name}{'-' + log_suffix if log_suffix else ''}.log"
        output = log.open("w")
        process_environment = os.environ.copy()
        if environment is not None:
            process_environment.update(environment)
        process = subprocess.Popen([str(self.evidence / "menu"), "client", self.test_id, mode],
                                   stdout=output, stderr=subprocess.STDOUT, env=process_environment)
        output.close()
        self.children.append(process)
        return process, log

    def join_client(self, process, log, marker):
        if process.wait(timeout=20) != 0:
            raise AssertionError(f"Background client failed: {log}")
        self.contains(log.read_text(), marker)

    def prepare(self):
        print(f"Evidence: {self.evidence}", flush=True)
        self.command(["swift", "build", "--package-path", self.package_path,
                      "--product", "maccompanion-agent-xpc-test"], timeout=600, name="build")
        bin_path = self.command(["swift", "build", "--package-path", self.package_path,
                                 "--show-bin-path"], timeout=60, name="bin-path").strip().splitlines()[-1]
        binary = Path(bin_path) / "maccompanion-agent-xpc-test"
        identity = os.environ.get("MACCOMPANION_XPC_PROBE_SIGNING_IDENTITY", "Developer ID Application")
        for name, identifier in (("agent", "media.jenny.maccompanion.agent"),
                                 ("menu", "media.jenny.maccompanion"),
                                 ("wrong-menu", "media.jenny.maccompanion.xpc-test.wrong"),
                                 ("wrong-agent", "media.jenny.maccompanion.agent.wrong")):
            target = self.evidence / name
            shutil.copy2(binary, target)
            self.command(["codesign", "--force", "--sign", identity, "--timestamp=none",
                          "--options", "runtime", "--identifier", identifier, target], name=f"sign-{name}")
            self.command(["codesign", "--verify", "--strict", target], name=f"verify-{name}")
        raw = self.evidence / "raw"
        self.command(["xcrun", "clang", "-std=c11", "-fblocks", "-mmacosx-version-min=26.0",
                      ROOT / "Experiments/LiveControlLab/Sources/AgentXPCRawProbe/main.c", "-o", raw], name="build-raw")
        shutil.copy2(raw, self.evidence / "adhoc")
        for name, signer in (("raw", identity), ("adhoc", "-")):
            self.command(["codesign", "--force", "--sign", signer, "--timestamp=none",
                          "--identifier", "media.jenny.maccompanion", self.evidence / name], name=f"sign-{name}")

    def matrix(self):
        for mode, marker in (("firstUnlock", "first-unlock-deferred"),
                             ("preparationFailure", "startup-failed-closed"),
                             ("invalidRevision", "startup-failed-closed")):
            self.case(mode, lambda m=mode, s=marker: self.client(m, binary="agent", role="server", marker=s))
        self.case("no-service-rejected", lambda: self.client("absent", marker="connection-rejected"))
        self.start_server()
        self.case("disabled-denies-readiness", lambda: self.client("denied-ready", marker="readiness-rejected"))
        self.case("durable-enable-receipt", lambda: self.client("enable", role="bootstrap", marker="enabled-receipt-verified"))
        self.wait_marker(self.server_log, "restart-requested")
        self.case("disabled-concurrent-finish", self.stop_server)
        self.case("listener-failure-no-fallback", lambda: self.client("listenerFailure", binary="agent", role="server", marker="startup-failed-closed"))
        self.start_server()
        self.case("restart-loads-enabled-intent", lambda: self.client("status", marker="status-verified"))
        self.case("enabled-denies-bootstrap", lambda: self.client("denied", role="bootstrap", marker="bootstrap-rejected"))
        self.case("status-before-ready", lambda: self.client("before-ready", marker="pre-readiness-rejected"))
        self.case("duplicate-ready", lambda: self.client("duplicate-ready", marker="duplicate-readiness-rejected"))
        self.case("same-instance-reconnect", lambda: self.client("reconnect", marker="reconnect-verified"))
        self.case("wrong-menu-identity", lambda: self.client("reject", binary="wrong-menu", marker="connection-rejected"))
        for mode in ("version", "extra"):
            self.case(f"malformed-hello-{mode}", lambda m=mode: self.contains(
                self.command([self.evidence / "raw", self.label, m], name=f"raw-{m}"), "raw-peer-rejected"))
        self.case("adhoc-peer-rejected-by-server", lambda: self.contains(
            self.command([self.evidence / "adhoc", self.label, "exact"], name="adhoc-peer"), "raw-peer-rejected"))
        def supersede():
            process, log = self.background_client("wait-invalidation")
            self.wait_marker(log, "waiting-for-invalidation")
            self.client("status", marker="status-verified")
            self.join_client(process, log, "peer-loss-observed")
        self.case("new-menu-retires-old-generation", supersede)
        self.case("enabled-concurrent-finish", self.stop_server)
        self.start_server(binary="wrong-agent")
        self.case("wrong-agent-identity", lambda: self.client("reject", marker="connection-rejected"))
        assert "menu-ready" not in self.server_log.read_text().splitlines()
        self.stop_server()
        self.start_server("unavailable")
        self.case("unavailable-status-without-disconnect", lambda: self.client("unavailable", marker="unavailable-status-verified"))
        self.stop_server()
        self.start_server("slow")
        self.case("status-timeout-drops-late-reply", lambda: self.client("timeout", marker="pending-read-failed-closed"))
        self.wait_marker(self.server_log, "late-status-returned")
        def die_during_read():
            old_reads = self.server_log.read_text().splitlines().count("status-read-started")
            process, log = self.background_client("pending-death")
            deadline = time.monotonic() + 10
            while self.server_log.read_text().splitlines().count("status-read-started") <= old_reads:
                if time.monotonic() > deadline:
                    raise AssertionError("Pending status read did not reach the server")
                time.sleep(.02)
            self.stop_server(abrupt=True)
            self.join_client(process, log, "pending-read-failed-closed")
        self.case("agent-death-during-pending-read", die_during_read)
        self.start_server()
        self.case("recovery-after-agent-death", lambda: self.client("reconnect", marker="reconnect-verified"))
        self.stop_server()

        # Real primary services/storage/lifecycle/status; only custody, inert
        # Interactive and the no-op process starter are platform substitutes.
        self.start_server("productionPrimary")
        self.wait_marker(self.server_log, "primary-identity-established")
        self.case("primary-production-status", lambda: self.client("production", marker="production-lifecycle-status-verified"))
        self.case("primary-production-denies-bootstrap", lambda: self.client("denied", role="bootstrap", marker="bootstrap-rejected"))
        self.case("primary-production-reconnect", lambda: self.client("reconnect", marker="reconnect-verified"))
        self.case("primary-production-peer-retirement", supersede)
        self.case("primary-production-concurrent-finish", self.stop_server)

        database = self.state / "media.jenny.maccompanion/Agent/v1/security-v1.sqlite3"
        def persisted_identity():
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                rows = connection.execute("SELECT * FROM host_identity").fetchall()
                assert len(rows) == 1
                return rows
        identity_before = persisted_identity()
        def restart_primary():
            self.start_server("productionPrimary")
            self.wait_marker(self.server_log, "primary-identity-reloaded")
            self.client("production", marker="production-lifecycle-status-verified")
            assert persisted_identity() == identity_before, "Persisted identity changed across restart"
        self.case("primary-production-restart-identity", restart_primary)
        self.stop_server(abrupt=True)
        self.case("primary-production-abrupt-restart", restart_primary)
        self.stop_server()

        def missing_key():
            key = database.parent / "isolated-software-key.bin"
            saved = database.parent / "isolated-software-key.saved"
            key.rename(saved)
            try:
                result = subprocess.run([str(self.evidence / "agent"), "server", self.test_id, "productionPrimary"],
                                        capture_output=True, text=True, timeout=15)
                assert result.returncode != 0 and "failure:missingEstablishedKey" in result.stdout.splitlines()
                assert "service-running" not in result.stdout and not key.exists()
                assert persisted_identity() == identity_before
            finally:
                saved.rename(key)
        self.case("primary-production-missing-key-fails-closed", missing_key)

        self.start_server("productionPresentation")
        def presentation():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation"], name="presentation")
            for marker in ("presentation-delivery-idempotence-verified", "pairing-create-dismiss-retry-verified",
                           "grant-without-device-rejected", "status-verified"):
                self.contains(text, marker)
            self.wait_marker(self.server_log, "presentation-cycle-complete")
            self.wait_marker(self.server_log, "service-running")
            assert "presentation-cycle-failed" not in self.server_log.read_text().splitlines()
        self.case("production-menu-presentation-and-pairing", presentation)
        def loopback_binding():
            self.wait_marker(self.server_log, "isolated-loopback-ready")
            text = self.command(["lsof", "-nP", "-a", "-p", str(self.agent_pids[-1]),
                                 "-iTCP:59654", "-sTCP:LISTEN", "-Fn"], name="loopback-binding")
            endpoints = [line for line in text.splitlines() if line.startswith("n")]
            assert endpoints == ["n127.0.0.1:59654"], "Test listener is not exclusively loopback"
        self.case("production-loopback-binding", loopback_binding)
        def outstanding_qr():
            lost = self.server_log.read_text().splitlines().count("invalidated-menu")
            self.client("presentation-abandon", marker="outstanding-qr-created")
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if self.server_log.read_text().splitlines().count("invalidated-menu") > lost:
                    break
                time.sleep(.02)
            else:
                raise AssertionError("No exact menu-loss event")
            self.client("presentation-recover-qr", marker="replacement-menu-qr-verified")
        self.case("production-menu-loss-outstanding-qr", outstanding_qr)
        def durable_sequence():
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                rows = connection.execute("SELECT generation, next_revision FROM status_sequence").fetchall()
                assert len(rows) <= 1
                return rows[0] if rows else None
        def real_client(mode):
            before = durable_sequence()
            text = self.command([self.evidence / "menu", "client", self.test_id, mode], name=mode)
            for marker in ("real-primary-authentication-verified", "real-observe-sequence-verified",
                           "paired-agent-status-verified"):
                self.contains(text, marker)
            if mode == "presentation-pair":
                self.contains(text, "real-pairing-pin-and-sas-verified")
                self.contains(text, "real-pairing-approved-and-persisted")
                self.contains(text, "real-pairing-exact-replay-and-mutation-rejection-verified")
            after = durable_sequence()
            assert after is not None and after[1] >= 2, "Observe sequence not durably stored"
            if before is not None:
                assert after[0] == before[0] and after[1] >= before[1] + 2, "Observe sequence not durably advanced"
        self.case("production-real-client-pairing", lambda: real_client("presentation-pair"))
        self.case("production-real-client-reconnect", lambda: real_client("presentation-reconnect"))
        self.case("production-menu-concurrent-finish", self.stop_server)
        def paired_restart():
            self.start_server("productionPaired")
            self.wait_marker(self.server_log, "primary-identity-reloaded")
            real_client("presentation-reconnect")
            self.wait_marker(self.server_log, "service-running")
            assert persisted_identity() == identity_before
        self.case("production-real-client-agent-restart", paired_restart)
        self.stop_server(abrupt=True)
        self.case("production-real-client-agent-crash-restart", paired_restart)
        self.stop_server()
        self.start_server("productionInteractive")
        def act_denial():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-act-denial"], name="act-remote-denial")
            for marker in ("act-host-ungranted-invoke-denied", "act-host-unknown-status-and-cancel-opaque", "paired-agent-status-verified"):
                self.contains(text, marker)
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                assert connection.execute("SELECT count(*) FROM durable_operations").fetchone()[0] == 0
                assert connection.execute("SELECT count(*) FROM device_grants").fetchone()[0] == 0
            assert "isolated-audio-execution:" not in self.server_log.read_text()
        self.case("production-act-remote-ungranted-denial", act_denial)
        def act():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-act"], name="act-journey", timeout=45)
            for marker in ("act-client-ungranted-operation-rejected", "signed-act-decline-and-changed-replay-rejected",
                           "signed-act-approval-fences-primary-and-reconnects", "act-execute-readback-and-exact-replay-verified",
                           "act-mismatched-readback-fails-closed", "act-completes-without-control-preserves-observe",
                           "paired-agent-status-verified"):
                self.contains(text, marker)
            calls = [line for line in self.server_log.read_text().splitlines() if line.startswith("isolated-audio-execution:")]
            assert calls == ["isolated-audio-execution:1", "isolated-audio-execution:2", "isolated-audio-execution:3"], "duplicate or missing test audio execution"
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                assert connection.execute("SELECT capability_id FROM device_grants").fetchall() == [("maccompanion.system.setAudioMuted",)]
        self.case("production-signed-act-grant-and-operations", act)
        def act_restart_replay(abrupt=False):
            self.stop_server(abrupt=abrupt)
            self.start_server("productionInteractive")
            self.client("presentation-act-replay", marker="act-durable-status-and-invoke-replay-verified")
            assert not any(line.startswith("isolated-audio-execution:") for line in self.server_log.read_text().splitlines()), "replayed operation executed after restart"
        self.case("production-act-agent-restart-replay", act_restart_replay)
        self.case("production-act-agent-crash-restart-replay", lambda: act_restart_replay(True))
        def clear_audio_markers():
            # Only exact test-owned files, while the UUID-scoped Agent is stopped.
            assert not self.loaded
            for name in ("audio-effect-reached", "audio-effect-release"):
                database.parent.joinpath(name).unlink(missing_ok=True)
        def act_cancellation():
            self.stop_server()
            clear_audio_markers()
            self.start_server("productionActPaused")
            self.client("presentation-act-fault-cancel", marker="act-cancel-request-not-false-cancellation-success")
            lines = self.server_log.read_text().splitlines()
            assert lines.count("isolated-audio-execution:1") == 1
            assert lines.count("isolated-audio-cancellation-requested") == 1
            assert sum(line.startswith("isolated-audio-execution:") for line in lines) == 1
        self.case("production-act-same-primary-cancellation", act_cancellation)
        def act_inflight_crash():
            self.stop_server()
            clear_audio_markers()
            self.start_server("productionActPaused")
            client, log = self.background_client("presentation-act-fault-interrupt")
            self.wait_marker(log, "act-provider-effect-observed")
            operation = json.loads((self.state / "interrupted-act-operation.json").read_text())
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                assert connection.execute("SELECT state FROM durable_operations WHERE operation_id = ?", (operation.lower(),)).fetchone() == ("running",)
            self.stop_server(abrupt=True)
            self.join_client(client, log, "act-interrupted-primary-closed")
            self.start_server("productionInteractive")
            self.client("presentation-act-fault-recover", marker="act-interrupted-outcome-unknown-no-retry")
            assert "isolated-audio-execution:" not in self.server_log.read_text()
        self.case("production-act-inflight-crash-recovery", act_inflight_crash)
        def control():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-control"],
                                name="presentation-control", timeout=45)
            for marker in ("signed-control-grant-decline-approve-verified", "signed-interactive-admission-verified",
                           "production-lease-and-role-authentication-verified", "production-signed-lease-renewal-verified",
                           "production-stop-preserves-observe-verified", "paired-agent-status-verified"):
                self.contains(text, marker)
        self.case("production-signed-control-grant-and-runtime", control)
        self.case("production-final-admission-race", lambda: self.client("presentation-control-admission-race",
            marker="production-final-admission-race-rejected"))
        self.case("production-menu-loss-retires-control", lambda: self.client("presentation-control-menu-loss",
            marker="production-menu-loss-retires-runtime-preserves-observe"))
        self.case("production-unconfirmed-revocation-review", lambda: self.client("presentation-revocation-review",
            marker="unconfirmed-revocation-review-created"))
        def revocation_state():
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                rows = connection.execute("SELECT state, authorization_epoch, grant_revision FROM device_authorizations").fetchall()
                assert len(rows) == 1
                return (rows[0], connection.execute("SELECT count(*) FROM device_grants").fetchone()[0],
                        connection.execute("SELECT count(*) FROM device_revocation_commands WHERE completed_at_ms IS NOT NULL").fetchone()[0],
                        connection.execute("SELECT count(*) FROM security_events WHERE event_kind = 'device.revoke'").fetchone()[0])
        before_revoke = revocation_state()
        assert before_revoke[0][0] == "activeGranted" and before_revoke[1] > 0 and before_revoke[2:] == (0, 0)
        def revoke():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-control-revoke"], name="active-revocation")
            for marker in ("prior-menu-revocation-review-rejected", "changed-review-request-replay-rejected",
                           "replaced-review-revocation-rejected", "changed-revocation-replay-rejected",
                           "signed-revocation-retires-primary-and-control", "paired-agent-status-verified"):
                self.contains(text, marker)
            after = revocation_state()
            assert after == (("revoked", before_revoke[0][1] + 1, before_revoke[0][2] + 1), 0, 1, 1)
        self.case("production-signed-active-device-revocation", revoke)
        def replay_revocation():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-revocation-replay"], name="revocation-replay")
            for marker in ("durable-revocation-replay-verified", "revoked-client-reconnect-rejected", "paired-agent-status-verified"):
                self.contains(text, marker)
            assert revocation_state() == (("revoked", before_revoke[0][1] + 1, before_revoke[0][2] + 1), 0, 1, 1)
        self.case("production-revoked-client-reconnect", replay_revocation)
        self.stop_server()
        self.start_server("productionInteractive")
        self.case("production-revocation-agent-restart", replay_revocation)
        self.stop_server(abrupt=True)
        self.start_server("productionInteractive")
        self.case("production-revocation-agent-crash-restart", replay_revocation)
        def revocation_race():
            text = self.command([self.evidence / "menu", "client", self.test_id, "presentation-control-revocation-race"], name="revocation-race")
            for marker in ("real-pairing-approved-and-persisted", "signed-control-grant-decline-approve-verified",
                           "revocation-race-desktop-pause-observed", "revocation-race-primary-fenced-before-desktop-resume",
                           "production-revocation-during-preparation-rejected", "paired-agent-status-verified"):
                self.contains(text, marker)
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                assert connection.execute("SELECT count(*) FROM device_authorizations WHERE state = 'revoked'").fetchone()[0] == 2
                assert connection.execute("SELECT count(*) FROM device_grants").fetchone()[0] == 0
                assert connection.execute("SELECT count(*) FROM device_revocation_commands WHERE completed_at_ms IS NOT NULL").fetchone()[0] == 2
                assert connection.execute("SELECT count(*) FROM security_events WHERE event_kind = 'device.revoke'").fetchone()[0] == 2
        self.case("production-revocation-during-preparation", revocation_race)
        self.stop_server()

        names = [case["name"] for case in self.cases]
        if set(names) != EXPECTED_CASES or len(names) != len(EXPECTED_CASES):
            raise AssertionError("Incomplete or duplicate integration matrix")
        if source_fingerprint() != self.source_sha256:
            raise AssertionError("Source changed during the integration run")

    def cleanup(self):
        # Exact UUID label and child handles only, never a production process.
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=3)
        if subprocess.run(["launchctl", "print", self.job], capture_output=True, timeout=5).returncode == 0:
            try:
                self.capture_job_state("before-cleanup")
            except OSError:
                # Diagnostic storage exhaustion must not prevent exact-job
                # termination and private-state cleanup.
                pass
            result = subprocess.run(["launchctl", "bootout", self.job], capture_output=True, timeout=10)
            if result.returncode:
                raise RuntimeError("Disposable job cleanup failed; preserve evidence for recovery")
            self.loaded = False
        deadline = time.monotonic() + 3
        while subprocess.run(["launchctl", "print", self.job], capture_output=True, timeout=5).returncode == 0:
            if time.monotonic() >= deadline:
                raise RuntimeError("Disposable job remains registered")
            time.sleep(.05)
        self.wait_agent_exit()
        assert self.state.parent == Path("/private/tmp") and self.state.name == f"maccompanion-agent-xpc-{self.test_id}"
        shutil.rmtree(self.state)
        for name in ("agent", "menu", "wrong-menu", "wrong-agent", "raw", "adhoc", "disposable.plist"):
            (self.evidence / name).unlink(missing_ok=True)
        if any(child.poll() is None for child in self.children) or self.state.exists():
            raise RuntimeError("Disposable cleanup incomplete")


def main():
    def interrupted(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
    probe = Probe()
    failure = None
    cleaned = False
    try:
        probe.prepare()
        probe.matrix()
    except (Exception, KeyboardInterrupt) as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        try:
            probe.cleanup()
            cleaned = True
        except Exception as error:
            failure = f"{failure or ''} Cleanup: {error}"
    report = {"schema": 1, "status": "passed" if failure is None and cleaned else "failed",
              "cases": probe.cases, "cleanupVerified": cleaned, "failure": failure,
              "testID": probe.test_id, "serviceLabel": probe.label,
              "sourceSHA256": probe.source_sha256,
              "startedAtUnixSeconds": probe.started, "elapsedSeconds": round(time.time() - probe.started, 3),
              "limits": ["Original fault matrix injects preparation/status; primary-production cases use real primary/lifecycle/status owners",
                         "Software test identity custody and inert process starter; native mute provider uses a test-only in-memory audio controller, and earlier non-Control startup lanes keep Interactive unavailable",
                         "Presentation lane uses the production enabled coordinator and composition with a loopback listener; Bonjour readiness is explicitly substituted by confirmed private-endpoint readiness",
                         "Separate generated review transport case plus real client pairing, signed review approval, reconnect and durable Observe; local human approval and hardware key custody are substituted",
                         "Control lane uses real signed grant decisions, lease issuance/final admission, runtime owner/adapter, role authentication and scheduled renewals; active session/display/capture/indicator/input/media platform effects are explicitly substituted",
                         "Reviewed signed device revocation, stale review rejection, exact durable replay and revoked reconnect run through real Agent owners; separate administrative Stop/history/diagnostics remain untested",
                         "Act uses signed review/grants, real operations and native provider with fake audio; raw pinned/authenticated client proves host denial and same-primary status/cancel; pausing native result delivery proves cancelRequested is not cancelled and post-effect crash becomes outcomeUnknown without retry; no actual audio or hardware presence is exercised",
                         "Revocation during paused Desktop preparation must close primary before descriptor release and produce zero capture starts; this proves termination fencing, not a concurrent durable-row update bypassing that fence",
                         "No real screen capture, rendered video, posted input or surface/focus transitions in this lane",
                         "No installed app, SMAppService, production Keychain, TCC, LAN, Simulator, or physical iPhone",
                         "Debug beta-toolchain evidence; not stable release certification"]}
    (probe.evidence / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['status'].upper()}: {len(probe.cases)} checks; cleanup={cleaned}; {probe.evidence / 'report.json'}", flush=True)
    if failure:
        print(failure, flush=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
