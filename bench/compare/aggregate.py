import collections, statistics, sys
d = collections.defaultdict(list)
for line in open('logs/raw.txt'):
    p = line.split()
    if len(p) != 5: continue
    try: d[p[1]].append((float(p[2]), float(p[3]), float(p[4])))
    except ValueError: pass
print("| metric | median ns/op | min | max | allocs/op | bytes/op | runs |")
print("|---|---:|---:|---:|---:|---:|---:|")
for k, v in d.items():
    ns = [x[0] for x in v]
    print(f"| {k} | {statistics.median(ns):.2f} | {min(ns):.2f} | {max(ns):.2f} | {statistics.median([x[1] for x in v]):.4f} | {statistics.median([x[2] for x in v]):.1f} | {len(v)} |")
