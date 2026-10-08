#!/usr/bin/env python3
"""Summarize content-free normal-app transition diagnostics.

Success ends at inputReady. Host selection replies and partial attempts do not
count as successful switches. This report is diagnostic, not release acceptance.
"""
import argparse
import json
import math
from pathlib import Path
import re
import unittest

STAGES = ("fenced", "rendererDrained", "enrollmentDrained", "hostAcknowledged",
          "nativePrepared", "firstFrame", "inputReady")
TERMINAL = {"inputReady", "failed", "cancelled"}
EVENT = re.compile(r"event=view-transition\.([A-Za-z]+) attempt=([A-Fa-f0-9-]{36}) elapsedMs=(\d+)(?: |$)")
ERROR = re.compile(r"errorType=([A-Za-z0-9_.]+)")
CODE = re.compile(r"errorCode=([A-Za-z]+)")
TIMESTAMP = re.compile(r"^timestamp=(\d{1,12}\.\d{3}) ")
SURFACE_PROGRESS = re.compile(
    r"event=native\.launch\.native\.video\.surface-(presented|frames-advanced|frames-stalled) "
    r"attempt=([A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12})(?: |$)"
)


def surface_progress(lines, expected_presentations):
    """Count presentation generations, rather than repeated IDR callbacks.

    Every expected generation must present and then advance. Repeated callbacks
    cannot supply a missing generation or erase a stall/invalid event order.
    """
    presented, advanced, stalled = set(), set(), set()
    occurrences = {stage: 0 for stage in ("presented", "frames-advanced", "frames-stalled")}
    invalid = 0
    for line in lines:
        match = SURFACE_PROGRESS.search(line) if len(line) <= 2048 else None
        if not match:
            continue
        stage, attempt = match.groups()
        occurrences[stage] += 1
        if stage == "presented":
            presented.add(attempt)
        else:
            if attempt not in presented:
                invalid += 1
            (advanced if stage == "frames-advanced" else stalled).add(attempt)
    return {
        "presentedFrameAttempts": len(presented),
        "advancingFrameAttempts": len(advanced),
        "presentationCallbacks": occurrences["presented"],
        "advancingFrameCallbacks": occurrences["frames-advanced"],
        "stalledFrameAttempts": len(stalled),
        "invalidProgressEvents": invalid,
        "everyPresentationAdvanced": (len(presented) == expected_presentations
            and advanced == presented and not stalled and invalid == 0),
    }


def diagnostic_window(lines, start_unix, end_unix):
    if not (math.isfinite(start_unix) and math.isfinite(end_unix)
            and 0 < start_unix <= end_unix):
        raise ValueError("Expected an ordered finite diagnostic window")
    selected = []
    for line in lines:
        match = TIMESTAMP.match(line) if len(line) <= 2048 else None
        if match and start_unix <= float(match.group(1)) <= end_unix:
            selected.append(line)
    return selected


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] if ordered else None


def summarize(lines):
    attempts = {}
    rejected = 0
    for line in lines:
        if len(line) > 2048:
            rejected += 1
            continue
        event = EVENT.search(line)
        if not event:
            continue
        stage, attempt, elapsed = event.groups()
        elapsed = int(elapsed)
        if stage not in (*STAGES, "failed", "cancelled") or elapsed > 3_600_000:
            rejected += 1
            continue
        current = attempts.setdefault(attempt, {"stages": {}, "status": "incomplete"})
        if stage in current["stages"] or current["status"] != "incomplete":
            rejected += 1
            current["invalid"] = True
            continue
        if current["stages"] and elapsed < max(current["stages"].values()):
            rejected += 1
            current["invalid"] = True
        earlier = [STAGES.index(item) for item in current["stages"] if item in STAGES]
        if stage in STAGES and earlier and STAGES.index(stage) <= max(earlier):
            rejected += 1
            current["invalid"] = True
        current["stages"][stage] = elapsed
        if stage in TERMINAL:
            current["status"] = {"inputReady": "succeeded", "failed": "failed", "cancelled": "cancelled"}[stage]
            error, code = ERROR.search(line), CODE.search(line)
            if error:
                current["errorType"] = error.group(1)
            if code:
                current["errorCode"] = code.group(1)
    counts = {status: 0 for status in ("succeeded", "failed", "cancelled", "incomplete", "invalid")}
    durations, segments, failures = [], {stage: [] for stage in STAGES[1:]}, {}
    records = []
    for attempt in attempts.values():
        stages = attempt["stages"]
        # Rotated logs may begin halfway through a switch. Missing stages must
        # remain incomplete; never improve the latency denominator by omission.
        if attempt.get("invalid"):
            attempt["status"] = "invalid"
        elif "fenced" not in stages or (attempt["status"] == "succeeded" and any(stage not in stages for stage in STAGES)):
            attempt["status"] = "incomplete"
        counts[attempt["status"]] += 1
        if attempt["status"] == "succeeded":
            durations.append(stages["inputReady"] - stages["fenced"])
            for before, after in zip(STAGES, STAGES[1:]):
                delta = stages[after] - stages[before]
                segments[after].append(delta)
        if attempt["status"] == "failed":
            key = attempt.get("errorCode", attempt.get("errorType", "unspecified"))
            failures[key] = failures.get(key, 0) + 1
        records.append(attempt)
    total = len(attempts)
    return {"profile": "maccompanion.native-view-transition-report.v1", "evidenceClass": "diagnosticOnly",
            "counts": counts, "attempts": total, "rejectedEvents": rejected,
            "successRate": counts["succeeded"] / total if total else None,
            "elapsedMilliseconds": {"p50": percentile(durations, .50), "p95": percentile(durations, .95),
                                    "maximum": max(durations) if durations else None},
            "stageP95Milliseconds": {stage: percentile(values, .95) for stage, values in segments.items()},
            "failures": failures, "measurements": records,
            "releaseAccepted": False}


class ReportTests(unittest.TestCase):
    def events(self, stages, identifier="11111111-2222-4333-8444-555555555555"):
        return [f"timestamp=1.000 event=view-transition.{stage} attempt={identifier} elapsedMs={time}\n" for stage, time in stages]

    def test_full_success_and_host_ack_only_are_distinct(self):
        lines = self.events(zip(STAGES, (0, 100, 200, 400, 800, 900, 1000)))
        lines += self.events((("fenced", 0), ("hostAcknowledged", 200)), "22222222-2222-4333-8444-555555555555")
        report = summarize(lines)
        self.assertEqual(report["counts"]["succeeded"], 1)
        self.assertEqual(report["counts"]["incomplete"], 1)
        self.assertEqual(report["successRate"], .5)
        self.assertEqual(report["elapsedMilliseconds"]["p95"], 1000)

    def test_failed_and_cancelled_attempts_are_counted(self):
        lines = self.events((("fenced", 0), ("failed", 300)))
        lines[-1] = lines[-1].rstrip() + " errorType=Test.Unavailable errorCode=primaryUnavailable\n"
        lines += self.events((("fenced", 0), ("cancelled", 200)), "22222222-2222-4333-8444-555555555555")
        report = summarize(lines)
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["counts"]["cancelled"], 1)
        self.assertEqual(report["failures"], {"primaryUnavailable": 1})
        self.assertIsNone(report["elapsedMilliseconds"]["p95"])

    def test_rotated_and_out_of_order_logs_cannot_count_as_success(self):
        self.assertEqual(summarize(self.events((("inputReady", 1),)))["counts"]["incomplete"], 1)
        lines = self.events(zip(STAGES, (0, 100, 200, 400, 800, 700, 1000)))
        self.assertEqual(summarize(lines)["counts"]["invalid"], 1)
        wrong_stage_order = self.events((('fenced', 0), ('rendererDrained', 100),
            ('enrollmentDrained', 200), ('hostAcknowledged', 300),
            ('firstFrame', 400), ('nativePrepared', 500), ('inputReady', 600)))
        self.assertEqual(summarize(wrong_stage_order)["counts"]["invalid"], 1)

    def test_previous_campaign_cannot_improve_current_campaign(self):
        old = self.events(zip(STAGES, (0, 100, 200, 400, 800, 900, 1000)))
        new = [line.replace("timestamp=1.000", "timestamp=2.000") for line in
               self.events((("fenced", 0), ("failed", 300)), "22222222-2222-4333-8444-555555555555")]
        report = summarize(diagnostic_window(old + new, 1.5, 2.5))
        self.assertEqual(report["attempts"], 1)
        self.assertEqual(report["counts"]["succeeded"], 0)
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["successRate"], 0)

    def test_repeated_keyframes_do_not_supply_missing_presentations(self):
        attempt = "11111111-2222-4333-8444-555555555555"
        events = [f"event=native.launch.native.video.surface-{stage} attempt={attempt}"
                  for stage in ("presented", "presented", "frames-advanced", "presented")]
        report = surface_progress(events, 1)
        self.assertTrue(report["everyPresentationAdvanced"])
        self.assertEqual(report["presentedFrameAttempts"], 1)
        self.assertEqual(report["presentationCallbacks"], 3)
        self.assertFalse(surface_progress(events, 2)["everyPresentationAdvanced"])

    def test_missing_mismatched_stalled_and_out_of_order_frames_fail(self):
        first = "11111111-2222-4333-8444-555555555555"
        second = "22222222-2222-4333-8444-555555555555"
        event = lambda stage, attempt=first: f"event=native.launch.native.video.surface-{stage} attempt={attempt}"
        for events in ([event("presented")],
                       [event("presented"), event("frames-advanced", second)],
                       [event("presented"), event("frames-stalled"), event("frames-advanced")],
                       [event("frames-advanced"), event("presented")]):
            with self.subTest(events=events):
                self.assertFalse(surface_progress(events, 1)["everyPresentationAdvanced"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--start-unix", type=float)
    parser.add_argument("--end-unix", type=float)
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ReportTests))
        if not result.wasSuccessful():
            raise SystemExit(1)
    if args.log:
        if not args.log.is_file() or args.log.is_symlink() or args.log.stat().st_size > 8 * 1024 * 1024:
            raise ValueError("Expected a bounded regular diagnostic log")
        lines = args.log.read_text().splitlines()
        if args.start_unix is not None or args.end_unix is not None:
            if args.start_unix is None or args.end_unix is None:
                parser.error("Provide both diagnostic window bounds")
            lines = diagnostic_window(lines, args.start_unix, args.end_unix)
        report = json.dumps(summarize(lines), indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.write_text(report)
        else:
            print(report, end="")
    elif not args.self_test:
        parser.error("Provide --log or --self-test")


if __name__ == "__main__":
    main()
