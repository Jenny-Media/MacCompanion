#!/usr/bin/env python3
"""Measure one bounded synthetic round trip; no screen or device interaction."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', required=True, type=Path)
    parser.add_argument('--seconds', type=int, default=3600)
    parser.add_argument('--output-dir', type=Path, help='New durable output directory; must not already exist')
    parser.add_argument('--lan-only', action='store_true', help='Exclude VPN/cellular adapters, matching the native app probe')
    args = parser.parse_args()
    if not 10 <= args.seconds <= 3600: parser.error('seconds must be 10..3600')
    if args.output_dir:
        root = args.output_dir.resolve()
        root.mkdir(parents=True, exist_ok=False)
    else:
        root = Path(tempfile.mkdtemp(prefix='maccompanion-webrtc-soak-', dir='/private/tmp'))
    print(root, flush=True)
    observations = []
    start = time.monotonic()
    with (root/'events.jsonl').open('w') as output, (root/'stderr.log').open('w') as errors:
        command = [str(args.executable), '--seconds', str(args.seconds)]
        if args.lan_only: command.append('--lan-only')
        process = subprocess.Popen(command, stdout=output, stderr=errors)
        try:
            while process.poll() is None:
                elapsed = time.monotonic() - start
                if elapsed > args.seconds + 60: raise TimeoutError('round trip exceeded bounded duration')
                row = subprocess.run(['ps', '-o', 'rss=,pcpu=', '-p', str(process.pid)], text=True, capture_output=True)
                fields = row.stdout.split()
                if len(fields) == 2:
                    observations.append({'elapsedSeconds':elapsed,'rssMiB':float(fields[0])/1024,'cpuPercent':float(fields[1])})
                    (root/'resources.json').write_text(json.dumps(observations,indent=2)+'\n')
                time.sleep(5)
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill();process.wait(timeout=10)
    events = [json.loads(line) for line in (root/'events.jsonl').read_text().splitlines()]
    results = [event for event in events if event.get('event')=='result']
    record = {'exitCode':process.returncode,'elapsedSeconds':time.monotonic()-start,
              'localNetworkOnly':args.lan_only,
              'roundTripPassed':process.returncode==0 and len(results)==1 and results[0]['passed'],
              'resourceSamples':len(observations),'oneHourGrowthVerified':False}
    warmed = [row for row in observations if row['elapsedSeconds']>=600]
    if args.seconds==3600 and len(warmed)>=300:
        first=[row['rssMiB'] for row in warmed if row['elapsedSeconds']<1200]
        last=[row['rssMiB'] for row in warmed if row['elapsedSeconds']>=3000]
        if first and last:
            x=[row['elapsedSeconds']/60 for row in warmed];y=[row['rssMiB'] for row in warmed]
            mean_x=statistics.mean(x);mean_y=statistics.mean(y)
            slope=sum((a-mean_x)*(b-mean_y) for a,b in zip(x,y))/sum((a-mean_x)**2 for a in x)
            growth=statistics.median(last)-statistics.median(first)
            record.update({'oneHourGrowthVerified':True,'medianWindowGrowthMiB':growth,
                           'rssSlopeMiBPerMinute':slope,'growthPassed':growth<=32 and slope<=1})
    record['passed']=record['roundTripPassed'] and (args.seconds!=3600 or record.get('growthPassed',False))
    (root/'result.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record),flush=True)
    raise SystemExit(0 if record['passed'] else 1)


if __name__ == '__main__': main()
