# Capability of the frozen benchmark: what it can prove, spec inputs, lasting faults.
# Run from the repository root: python3 Bench/scripts/capability.py
import json, glob, random, statistics as st, math, collections, re
random.seed(1)
B = 'Bench/data/measure/'
def cards(name):
    return {p.split(name + '/')[1].rsplit('/', 1)[0]: json.load(open(p))
            for p in sorted(glob.glob(B + name + '/*/*/scorecard.json'))}
pool, s1, s2 = cards('v1.6.9-baseline'), cards('v1.6.9-baseline-session1'), cards('v1.6.9-baseline-session2')

def ci(v, n=400):
    m = sorted(st.median(random.choices(v, k=len(v))) for _ in range(n))
    return m[int(.025 * n)], m[int(.975 * n) - 1]
def mw(a, b):
    al = sorted([(x, 0) for x in a] + [(x, 1) for x in b])
    r = {}; i = 0
    ranks = [0] * len(al)
    while i < len(al):
        j = i
        while j < len(al) and al[j][0] == al[i][0]: j += 1
        for k in range(i, j): ranks[k] = (i + j + 1) / 2
        i = j
    ra = sum(r for r, (x, g) in zip(ranks, al) if g == 0)
    n1, n2 = len(a), len(b)
    u = ra - n1 * (n1 + 1) / 2
    sd = math.sqrt(n1 * n2 * (n1 + n2 + 1) / 12)
    if sd == 0: return 1
    z = abs(u - n1 * n2 / 2) / sd
    return math.erfc(z / math.sqrt(2))
def changed(base, new):
    if len(set(base + new)) == 1: return False
    a, b = ci(base), ci(new)
    return (a[1] < b[0] or b[1] < a[0]) and mw(base, new) < .05

def family(k):
    if k.startswith('correctness'): return 'correctness'
    if 'cpu_pct' in k or 'memory' in k: return 'cpu/memory'
    if '.tx.' in k or '.rx.' in k: return 'traffic'
    if k.startswith('link'): return 'link delay'
    if any(s in k for s in ('tick_interval', 'queue_delay', 'frame_interval', 'tick_rate', 'frames_per', 'remote_move')): return 'pacing'
    if any(s in k for s in ('tick_ms', 'apply_us', 'draw_ms', 'send_completion', 'rebuild_ms', 'input_to_frame', 'join')): return 'duration'
    return 'other'

print('A. Can a 25% gain be proven? (one new session of 10 runs vs pooled baseline)')
res = collections.defaultdict(lambda: [0, 0, 0, 0])  # n, det both sessions, det 10%, false alarm
for sc in pool:
    grp = 'pair' if sc.startswith('pair') and 'soak' not in sc else ('soak' if 'soak' in sc else 'sweep')
    for k, m in pool[sc]['metrics'].items():
        if m['rule'] in ('reportOnly', 'verdict') or not m['repeatable']: continue
        f = family(k)
        if f in ('correctness', 'other'): continue
        if sc not in s1 or sc not in s2 or k not in s1[sc]['metrics'] or k not in s2[sc]['metrics']: continue
        a, b, base = s1[sc]['metrics'][k]['values'], s2[sc]['metrics'][k]['values'], m['values']
        if min(base) <= 0 or len(a) < 5 or len(b) < 5: continue
        r = res[(grp, f)]
        r[0] += 1
        r[1] += all(changed(base, [x * .75 for x in s]) for s in (a, b))
        r[2] += all(changed(base, [x * .90 for x in s]) for s in (a, b))
        r[3] += any(changed(base, s) for s in (a, b))
for k in sorted(res):
    n, d25, d10, fa = res[k]
    print(f'{k[0]:6s} {k[1]:11s} n={n:4d}  25%:{100*d25/n:4.0f}%  10%:{100*d10/n:4.0f}%  false:{100*fa/n:3.0f}%')

print('\nB. Spec inputs: median range across scenarios | worst mean+3sd | worst observed | not-repeatable count')
CTQ = ['host.tick_interval_ms.p95', 'guest.tick_interval_ms.p95', 'host.tick_interval_ms.over_25_pct',
       'guest.tick_interval_ms.over_25_pct', 'host.tick_ms.whole.p95', 'host.tick_ms.renderHop.p95',
       'guest.tick_ms.whole.p95', 'guest.input_to_frame_ms.p95', 'guest.frame_interval_ms.p95',
       'link.tcp.send_to_applied_ms.p95', 'link.position_delay_ms.host_to_guest.p95',
       'guest.remote_move_interval_ms.p50', 'guest.remote_move_interval_ms.p95',
       'guest.join_to_alive_ms', 'host.join_stall_ms', 'host.cpu_pct.mean', 'guest.cpu_pct.mean',
       'host.memory_mb.max', 'guest.memory_mb.max', 'host.tx.tcp.bytes_per_s', 'host.tx.udp.bytes_per_s',
       'link.udp.host_to_guest.loss_pct', 'link.udp.guest_to_host.loss_pct', 'link.tcp.unpaired',
       'host.invariant_violations', 'guest.invariant_violations', 'host.datagram_rejects', 'guest.datagram_rejects']
groups = {'pair': [s for s in pool if s.startswith('pair') and 'soak' not in s],
          'soak': [s for s in pool if 'soak' in s], 'n02': ['sweep/sweep-n02'], 'n04': ['sweep/sweep-n04']}
for k in CTQ:
    for g, scs in groups.items():
        ms = [pool[s]['metrics'][k] for s in scs if k in pool[s]['metrics']]
        if not ms: continue
        med = [m['median'] for m in ms]
        ucl = max(st.mean(m['values']) + 3 * st.pstdev(m['values']) for m in ms)
        mx = max(max(m['values']) for m in ms)
        nr = sum(not m['repeatable'] for m in ms)
        print(f'{k:42s} {g:4s} {min(med):9.2f}..{max(med):9.2f} | {ucl:9.2f} | {mx:9.2f} | {nr}/{len(ms)}')

print('\nC. Lasting faults by domain: scenario, domain.class, runs affected / runs, median count')
for sc in pool:
    for k, m in pool[sc]['metrics'].items():
        mm = re.match(r'correctness\.(\w+)\.(slow|persistent|terminal)$', k)
        if not mm or mm.group(1) in ('all', 'position', 'peerPosition', 'trees', 'terrainVariant'): continue
        v = m['values']; hit = sum(x > 0 for x in v)
        if hit: print(f'{sc.split("/")[1]:28s} {mm.group(1)}.{mm.group(2):10s} {hit:2d}/{len(v)}  median {st.median(v):.0f}  max {max(v):.0f}')

print('\nD. Spec metrics: scenarios where a 25% gain is proven / scenarios')
for k in CTQ:
    out = []
    for g, scs in groups.items():
        d = n = 0
        for sc in scs:
            m = pool[sc]['metrics'].get(k)
            if not m or min(m['values']) <= 0: continue
            a, b = s1[sc]['metrics'][k]['values'], s2[sc]['metrics'][k]['values']
            n += 1
            d += all(changed(m['values'], [x * .75 for x in s]) for s in (a, b))
        if n: out.append(f'{g} {d}/{n}')
    if out: print(f'{k:42s}', '  '.join(out))
