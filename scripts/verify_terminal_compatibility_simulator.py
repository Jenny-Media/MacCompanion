#!/usr/bin/env python3
"""Run synthetic protocol and opt-in real-tool Terminal tests in Simulator."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Experiments/TerminalCompatibilityQA'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--output', type=Path, required=True, help='New evidence directory outside the repository')
    parser.add_argument('--tmux', type=Path, default=shutil.which('tmux'))
    parser.add_argument('--zellij', type=Path, default=shutil.which('zellij'))
    parser.add_argument('--herdr', type=Path, default=shutil.which('herdr'))
    parser.add_argument('--screenshots', action='store_true', help='Pause on synthetic tool screens for external Simulator screenshot capture')
    parser.add_argument('--include-ui-regressions', action='store_true', help='Also verify existing toolbar, appearance and native-editing behavior')
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(ROOT) or args.output.exists():
        parser.error('--output must be a new directory outside the repository')
    tools = {name: Path(getattr(args, name)).expanduser().resolve() for name in ['tmux', 'zellij', 'herdr'] if getattr(args, name)}
    if not all(name in tools for name in ['tmux', 'zellij']):
        parser.error('tmux and Zellij executables are required; Herdr is optional and explicitly skipped when absent')
    for path in tools.values():
        if not Path(path).is_file():
            parser.error('Tool executable does not exist: ' + str(path))
    try:
        from host import ToolHost
    except ImportError:
        parser.error('Install the test-only Experiments/TerminalCompatibilityQA/requirements.txt in a temporary virtual environment')
    args.output.mkdir(parents=True)
    qa = args.build.resolve() / 'QA'
    previous_results = set(qa.glob('Results-*.xcresult'))
    with ToolHost(args.output, tools) as host:
        command = [sys.executable, str(ROOT / 'scripts/verify_terminal_pro_simulator.py'), '--build', str(args.build),
                   '--simulator', args.simulator, '--test-diagnostics', 'never', '--terminal-tool-host', str(host.descriptor_path),
                   '--only-testing', 'DirectClientTests/TerminalCompatibilityTests',
                   '--only-testing', 'DirectClientTests/TerminalToolIntegrationTests',
                   '--only-testing', 'DirectClientTests/TerminalIntegrationTests/testChangedHostKeyRejectsBeforeAnyPasswordAuthentication',
                   '--only-testing', 'DirectClientTests/TerminalIntegrationTests/testRealSSHTrustBeforeLoginInteractivePTYOrderedInputResizeAndPreservedShell']
        if args.screenshots: command += ['--screenshots']
        if args.include_ui_regressions:
            for identifier in [
                'AppearanceTests/testTerminalPaletteIsIndependentAndFollowsAppWhenSelectedWithoutNewSession',
                'TerminalDuoLayoutTests/testHostedTerminalDockFollowsKeyboardAcrossPaletteChanges',
                'TerminalDuoLayoutTests/testPersistentBarTogglesKeyboardAndKeepsFixedControlsWithScrollableKeys',
                'TerminalDuoLayoutTests/testNumbersRowVisibilityAppliesImmediatelyAndRestoresAcrossSessions',
                'KeyLibraryAndProTests/testIndexedTerminalKeysOneShotLockAndProtectedSettings',
            ]:
                command += ['--only-testing', 'DirectClientTests/' + identifier]
        with (args.output / 'runner.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    report = json.loads((args.output / 'tool-host-report.json').read_text())
    cleanup_ok = (report['remainingClientProcesses'] == report['remainingBridgeThreads'] == 0
                  and all(code == 0 for code in report['cleanupExitCodes'].values())
                  and report['descriptorRetired'] and not report['cleanupErrorTypes'] and not report['teardownErrorTypes'])
    results = set(qa.glob('Results-*.xcresult')) - previous_results
    result_bundle = max(results, key=lambda p: p.stat().st_mtime) if results else None
    summary = {}
    if result_bundle:
        extracted = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result_bundle), '--compact'],
                                   capture_output=True, text=True, timeout=30)
        if extracted.returncode == 0:
            summary = json.loads(extracted.stdout)
            (args.output / 'xctest-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    expected_count = 24 if args.include_ui_regressions else 19
    tests_ok = (summary.get('result') == 'Passed' and summary.get('totalTestCount') == expected_count
                and summary.get('expectedFailures') == 0 and summary.get('failedTests') == 0 and summary.get('skippedTests') == (0 if 'herdr' in tools else 1))
    status = {'simulator': args.simulator, 'runnerExitCode': result.returncode, 'cleanupVerified': cleanup_ok,
              'herdrAvailable': 'herdr' in tools, 'knownProductionGapsExpected': 0,
              'uiRegressionsIncluded': args.include_ui_regressions, 'expectedTestCount': expected_count,
              'intendedTestsVerified': tests_ok, 'totalTests': summary.get('totalTestCount'),
              'passedTests': summary.get('passedTests'), 'expectedFailures': summary.get('expectedFailures'),
              'failedTests': summary.get('failedTests'), 'skippedTests': summary.get('skippedTests'),
              'resultBundle': str(result_bundle) if result_bundle else None, 'qaEvidence': str(qa)}
    (args.output / 'run-summary.json').write_text(json.dumps(status, indent=2) + '\n')
    print(json.dumps(status, indent=2))
    return result.returncode or (0 if cleanup_ok and tests_ok else 1)


if __name__ == '__main__':
    raise SystemExit(main())
