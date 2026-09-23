#!/usr/bin/env python3
"""Connect disposable peers through local/paired-device files, retaining only counters."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid

BUNDLE = 'dev.maccompanion.webrtc.receiver'


def maintain_connection(host, output, transfer, original_offer, seconds):
    """Relay fresh peers for foreground resume within the original test lease."""
    started = time.monotonic()
    forwarded_request = None
    sent_offer = original_offer['session']
    sent_answer = original_offer['session']
    last_state = None
    with (output/'reconnect-events.jsonl').open('w') as events:
        def emit(value):
            value['elapsedSeconds'] = time.monotonic()-started
            events.write(json.dumps(value)+'\n'); events.flush()

        while time.monotonic()-started < seconds and time.time() < original_offer['expiresAt']:
            if (output/'stop-relay').exists():
                break
            try:
                current = read_exchange(host/'offer.json')
                # Paired-device transfers dominate this test harness's latency.
                # Read diagnostics and resume intent in one atomic snapshot.
                status_started = time.monotonic()
                if transfer('from', 'status.json', host/'receiver-status.json'):
                    path = host/'receiver-status.json'
                    if path.stat().st_size > 300_000:
                        raise ValueError('Receiver status exceeds bound')
                    status = json.loads(path.read_text())
                    emit({'event':'receiverStatus','receiver':status,
                          'transferSeconds':time.monotonic()-status_started})
                    if status['state'] != last_state:
                        print('Receiver: '+status['state'],flush=True)
                        last_state = status['state']
                    request = status.get('reconnectRequest')
                else:
                    request = None
                if isinstance(request, dict):
                    if len(json.dumps(request).encode()) > 4096:
                        raise ValueError('Reconnect request exceeds bound')
                    uuid.UUID(request['request']); uuid.UUID(request['previousSession'])
                    if (request['previousSession'] == current['session']
                            and request['generation'] == original_offer['generation']
                            and request['expiresAt'] == original_offer['expiresAt']
                            and request['request'] != forwarded_request):
                        path = host/'reconnect.pending.json'
                        path.write_text(json.dumps(request))
                        path.replace(host/'reconnect-request.json')
                        forwarded_request = request['request']
                        emit({'event':'requestForwarded'})
                        # Give the local host time to publish its offer before
                        # starting another expensive device diagnostics transfer.
                        deadline = time.monotonic() + 1.5
                        while time.monotonic() < deadline:
                            current = read_exchange(host/'offer.json')
                            if current.get('reconnectRequest') == forwarded_request:
                                break
                            if (output/'stop-relay').exists():
                                break
                            time.sleep(.05)
                current = read_exchange(host/'offer.json')
                if (current['session'] != sent_offer and current.get('reconnectRequest') == forwarded_request
                        and current['generation'] == original_offer['generation']
                        and current['expiresAt'] == original_offer['expiresAt']):
                    if transfer('to', host/'offer.json', 'offer.json'):
                        sent_offer = current['session']
                        emit({'event':'freshOfferForwarded','session':sent_offer})
                if sent_answer != sent_offer and transfer('from', 'answer.json', host/'answer.pending.json'):
                    answer = read_exchange(host/'answer.pending.json')
                    if (answer['session'] == sent_offer and answer.get('reconnectRequest') == forwarded_request
                            and answer['generation'] == original_offer['generation']
                            and answer['expiresAt'] == original_offer['expiresAt']):
                        (host/'answer.pending.json').replace(host/'answer.json')
                        sent_answer = sent_offer
                        emit({'event':'freshAnswerForwarded','session':sent_answer})
                if (host/'host-status.json').exists():
                    emit({'event':'hostStatus','host':json.loads((host/'host-status.json').read_text())})
            except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
                # A network interruption can make paired-device files unavailable.
                # Keep bounded retries; never reuse an old sample as current proof.
                emit({'event':'relayRetry','errorType':type(error).__name__})
            time.sleep(.25)
        emit({'event':'relayEnded'})


def read_exchange(path):
    if path.stat().st_size > 300_000:
        raise ValueError('Exchange file exceeds the experiment bound')
    value = json.loads(path.read_text())
    uuid.UUID(value['session'])
    if not 0 < value['generation'] < 256 or not time.time() < value['expiresAt'] < time.time() + 3700:
        raise ValueError('Invalid or expired experiment session')
    if not isinstance(value['sdp'], str) or len(value['sdp'].encode()) >= 262_144:
        raise ValueError('SDP exceeds the experiment bound')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host-session', required=True, type=Path)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument('--simulator')
    target.add_argument('--device')
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--observe-seconds', type=int, default=15)
    parser.add_argument('--maintain-seconds', type=int, default=0,
                        help='Keep the paired-device/local relay active for foreground reconnection (0..3600)')
    args = parser.parse_args()
    if not 5 <= args.observe_seconds <= 300:
        parser.error('observe-seconds must be 5..300')
    if not 0 <= args.maintain_seconds <= 3600:
        parser.error('maintain-seconds must be 0..3600')
    host = args.host_session.resolve()
    if not str(host).startswith('/private/tmp/maccompanion-webrtc-') or not host.is_dir():
        parser.error('host-session must be an existing disposable WebRTC directory')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'passed': False, 'physicalDevice': bool(args.device), 'glassLatencyMeasured': False}
    samples = []
    log = (host/'transfer.log').open('a')

    def command(parts):
        return subprocess.run(['xcrun'] + parts, stdout=log, stderr=log, timeout=20).returncode == 0

    if args.simulator:
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container',
            args.simulator, BUNDLE, 'data'], text=True, timeout=20).strip())/'Documents'
    else:
        container = None

    def transfer(direction, source, destination):
        if container:
            try:
                if direction == 'to':
                    temporary = container/(destination + '.pending')
                    shutil.copy2(source, temporary)
                    temporary.replace(container/destination)
                else:
                    shutil.copy2(container/source, destination)
                return True
            except FileNotFoundError:
                return False
        return command(['devicectl', 'device', 'copy', direction, '--device', args.device,
            '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE, '--timeout', '15',
            '--quiet', '--source', str(source) if direction == 'to' else 'Documents/'+source,
            '--destination', 'Documents/'+destination if direction == 'to' else str(destination)])

    try:
        deadline = time.monotonic() + 30
        while not (host/'offer.json').exists():
            if (host/'host-status.json').exists():
                state = json.loads((host/'host-status.json').read_text()).get('state', '')
                if 'failed' in state.lower() or 'permission required' in state.lower():
                    raise RuntimeError(state)
            if time.monotonic() >= deadline:
                raise TimeoutError('Host did not produce an offer')
            time.sleep(.5)
        offer = read_exchange(host/'offer.json')
        result.update({'session': offer['session'], 'generation': offer['generation'], 'realCapture': offer['capture']})
        if not transfer('to', host/'offer.json', 'offer.json'):
            raise RuntimeError('Offer transfer failed; inspect the private transfer log')
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if transfer('from', 'answer.json', host/'answer.pending.json'):
                try:
                    answer = read_exchange(host/'answer.pending.json')
                except (ValueError, KeyError):
                    time.sleep(.5)
                    continue
                if answer['session'] == offer['session'] and answer['generation'] == offer['generation']:
                    (host/'answer.pending.json').replace(host/'answer.json')
                    break
            time.sleep(.5)
        else:
            raise TimeoutError('Receiver did not answer the current session')
        print('Connection files exchanged.', flush=True)
        start = time.monotonic()
        while time.monotonic() - start < args.observe_seconds:
            if transfer('from', 'status.json', host/'receiver-status.json'):
                status = json.loads((host/'receiver-status.json').read_text())
                samples.append({'elapsedSeconds': time.monotonic()-start,
                    'matchesSession': status.get('session') == offer['session'], 'receiver': status})
                (output/'samples.json').write_text(json.dumps(samples, indent=2)+'\n')
            time.sleep(1)
        if (host/'host-status.json').exists():
            shutil.copy2(host/'host-status.json', output/'host-status.json')
        if not samples:
            raise RuntimeError('No current-session receiver diagnostics')
        first, last = samples[0]['receiver'], samples[-1]['receiver']
        frames = last.get('frames', {})
        elapsed = time.monotonic()-start
        recent = [row for row in samples if row['elapsedSeconds'] >= elapsed-10]
        recent_advance = (len(recent) >= 2 and frames.get('receivedValidFrames', 0) >
            recent[0]['receiver'].get('frames', {}).get('receivedValidFrames', 0))
        result.update({'receiver': last, 'observedSeconds': time.monotonic()-start,
            'lastSampleAgeSeconds': elapsed-samples[-1]['elapsedSeconds'],
            'recentFramesAdvanced': recent_advance,
            'validFramesAdvanced': frames.get('receivedValidFrames', 0) > first.get('frames', {}).get('receivedValidFrames', 0)})
        result['passed'] = (result['validFramesAdvanced'] and recent_advance
            and samples[-1]['matchesSession'] and elapsed-samples[-1]['elapsedSeconds'] < 5
            and last['state'] == 'Receiving' and not last['videoHidden']
            and frames.get('invalidMarkers') == 0 and frames.get('wrongGenerationFrames') == 0)
        # A captured window may repeat a pattern frame; preserve nonIncreasingFrames
        # without interpreting identical patterns as reordered RTP packets.
    except Exception as error:
        result['error'] = str(error)
    finally:
        (output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'receiver'}), flush=True)
    try:
        if result['passed'] and args.maintain_seconds:
            maintain_connection(host, output, transfer, offer, args.maintain_seconds)
    finally:
        log.close()
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
