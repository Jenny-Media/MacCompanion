#!/usr/bin/env python3
"""Summarize monotonic, same-owner, same-geometry intervals; never infer screen latency."""
import argparse, json, math, pathlib

def summarize(rows):
    intervals=[]; rejected=0
    for before,after in zip(rows,rows[1:]):
        a,b=before.get('counters',{}),after.get('counters',{})
        start,end=before.get('uptime'),after.get('uptime')
        valid=(before.get('schema')==after.get('schema')==1 and before.get('owner')==after.get('owner')
               and before.get('owner') and isinstance(start,(int,float)) and isinstance(end,(int,float))
               and math.isfinite(start) and math.isfinite(end) and .5<=end-start<=2.5
               and not a.get('sessionPaused',True) and not b.get('sessionPaused',True)
               and a.get('sessionInputReady') is True and b.get('sessionInputReady') is True
               and not a.get('probeAwaiting',False) and not b.get('probeAwaiting',False)
               and all(a.get(k)==b.get(k) and a.get(k) is not None for k in ('framebufferWidth','framebufferHeight','framebufferAllocations')))
        if not valid: rejected+=1;continue
        def delta(key,group=None):
            x,y=(a.get(group,{}),b.get(group,{})) if group else (a,b)
            x,y=x.get(key),y.get(key)
            return y-x if isinstance(x,(int,float)) and isinstance(y,(int,float)) and math.isfinite(x) and math.isfinite(y) and y>=x else None
        frames=delta('presentedFrames')
        if frames is None: rejected+=1;continue
        intervals.append({'seconds':end-start,'frames':frames,'bytes':delta('inboundBytes','desktopSSH'),
                          'workerCPU':delta('workerCPUTotalMS','pipeline'),'copyMS':delta('frameCopyTotalMS','pipeline')})
    duration=sum(x['seconds'] for x in intervals); frames=sum(x['frames'] for x in intervals)
    def rate(key,scale):
        subset=[x for x in intervals if x[key] is not None]
        seconds=sum(x['seconds'] for x in subset)
        return sum(x[key] for x in subset)/seconds*scale if seconds else None
    copied=[x for x in intervals if x['copyMS'] is not None]
    copiedFrames=sum(x['frames'] for x in copied)
    return {'schema':1,'acceptedIntervals':len(intervals),'rejectedIntervals':rejected,'seconds':duration,
            'uiCallbackFramesPerSecond':frames/duration if duration else None,
            'incomingRFBPayloadMbitPerSecond':rate('bytes',8/1e6),
            'decoderWorkerCPUPercentOneCore':rate('workerCPU',.1),
            'copyMillisecondsPerUICallback':sum(x['copyMS'] for x in copied)/copiedFrames if copiedFrames else None,
            'endToEndLatencyMeasured':False}

def main():
    p=argparse.ArgumentParser();p.add_argument('journal',type=pathlib.Path);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
    if a.journal.stat().st_size>4*1024*1024: p.error('Journal exceeds experiment limit')
    rows=[json.loads(line,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite JSON'))) for line in a.journal.read_text().splitlines() if line]
    report=summarize(rows);a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
