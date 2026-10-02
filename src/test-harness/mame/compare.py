#!/usr/bin/env python3
# compare.py label... : table of benchmark results (seconds) vs the first label
import sys, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
labels = sys.argv[1:]
data = {}
for l in labels:
    data[l] = {}
    for line in open(os.path.join(D, l + ".txt")):
        k, v = line.split()
        data[l][k] = int(v)
keys = [k for k in data[labels[0]]]
for l in labels[1:]:
    keys += [k for k in data[l] if k not in keys]
print(f"{'test':22}" + "".join(f"{l:>12}" for l in labels) + "".join(f"{'vs ' + labels[0]:>12}" for l in labels[1:]))
for k in keys:
    row = [data[l].get(k) for l in labels]
    kb = k.endswith("_kb")
    fmt = (lambda v: f"{v/1024:11.1f}M" if v is not None else f"{'-':>12}") if kb else (lambda v: f"{v/100:11.2f}s" if v is not None else f"{'-':>12}")
    line = f"{k:22}" + "".join(fmt(v) for v in row)
    for v in row[1:]:
        if v is not None and row[0]:
            line += f"{(v - row[0]) / row[0] * 100:+11.0f}%"
        else:
            line += f"{'':>12}"
    print(line)
