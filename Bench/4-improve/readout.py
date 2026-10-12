import json, glob, os, sys
base = "Bench/data/analyze/v1.6.9-analyze-session2"
cand = "Bench/data/improve/candidate1-2d-1a-4b-3b"

def load(root, tier, name):
    p = f"{root}/{tier}/{name}/scorecard.json"
    if not os.path.exists(p):
        return None
    return json.load(open(p))["metrics"]

def val(m, key):
    if m is None or key not in m:
        return None
    return m[key]

def fmt(v):
    if v is None:
        return "     -"
    x = v["median"]
    return f"{x:8.3g}"

def row(tier, name, keys):
    b, c = load(base, tier, name), load(cand, tier, name)
    out = []
    for k in keys:
        vb, vc = val(b, k), val(c, k)
        if vb is None or vc is None:
            out.append(f"{k.split('.',1)[1][:34]:34} base {fmt(vb)} cand {fmt(vc)}")
            continue
        mb, mc = vb["median"], vc["median"]
        ch = (mc - mb) / mb * 100 if mb else float("nan")
        # 25% rule: intervals must not overlap and change >= 25%
        sep = vc["high"] < vb["low"] or vc["low"] > vb["high"]
        flag = "CHANGE" if (sep and abs(ch) >= 25) else ""
        out.append(f"{k.split('.',1)[1][:34]:34} base {mb:8.3g} cand {mc:8.3g} {ch:+7.1f}% {flag}")
    return out

mode = sys.argv[1]
if mode == "keys":
    # list correctness-ish metric names present in the soak scorecards
    m = load(cand, "pair", "s8-soak-hidden")
    for k in sorted(m):
        if k.startswith("correctness"):
            print(k, m[k]["median"])
elif mode == "1a":
    keys = ["guest.drawn_remote_step_ms.p50", "guest.drawn_remote_step_ms.p95"]
    for s in sorted(os.listdir(f"{cand}/pair")):
        print(s)
        for l in row("pair", s, keys): print("  ", l)
elif mode == "2d":
    keys = ["host.tick_ms.whole.p95", "host.tick_ms.whole.p50", "host.tick_interval_ms.over_25_pct",
            "host.tick_ms.hopSound.p95", "host.tick_ms.renderHopWork.p95"]
    for tier in ("pair", "sweep"):
        for s in sorted(os.listdir(f"{cand}/{tier}")):
            if tier == "pair" and not s.startswith("s8"):
                continue
            print(tier, s)
            for l in row(tier, s, keys): print("  ", l)
elif mode == "corr":
    keys = sys.argv[2:]
    for s in ("s8-soak-hidden", "s8-soak-open"):
        print(s)
        for l in row("pair", s, keys): print("  ", l)
elif mode == "runs":
    names = sys.argv[2:]
    for s in sorted(os.listdir(f"{cand}/pair")):
        b, c = load(base, "pair", s), load(cand, "pair", s)
        for k in names:
            vb, vc = val(b, k), val(c, k)
            if vb is None or vc is None:
                continue
            nb = sum(1 for x in vb["values"] if x > 0); nc = sum(1 for x in vc["values"] if x > 0)
            if nb or nc:
                print(f"{s:28} {k.split('.',1)[1]:28} runs with fault: base {nb}/{len(vb['values'])}  cand {nc}/{len(vc['values'])}   median base {vb['median']:.3g} cand {vc['median']:.3g}")
