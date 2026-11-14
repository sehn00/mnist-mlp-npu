"""
vcd_compare.py : 두 시뮬레이션의 파형(VCD)을 "클럭마다 한 번" 샘플해서 비교 (리뷰용)

같은 배선 후 넷리스트를 (A) 지연 없이, (B) SDF 지연을 넣고 돌린 결과를 비교해서
몇 번째 클럭에 어느 신호부터 달라지는지 찾는다.

샘플 시점 (클럭 핀의 상승 엣지 = 5 ns + 10 ns x k 기준)
  A (지연 없음) : 엣지 0.1 ns 전            -> 그 클럭 동안 정착된 값
  B (지연 포함) : 엣지 +OFF ns (기본 1.0)   -> 칩 안의 플립플롭에 클럭이 도착하기 전 (클럭 삽입 지연이 1.35 ns 이상)
                                                이고, 앞 클럭의 조합 회로는 다 정착한 뒤

사용법: python scripts/review/vcd_compare.py <A.vcd> <B.vcd> [OFF_ns] [최대 클럭 수]
"""
import sys, bisect

def parse(path):
    sigs = {}      # id -> list of full names
    width = {}
    changes = {}   # id -> ([times], [values])
    scope = []
    ts = 1
    t = 0
    with open(path, "r", errors="replace") as f:
        in_defs = True
        for line in f:
            line = line.strip()
            if not line: continue
            if in_defs:
                if line.startswith("$timescale"):
                    txt = line
                    while "$end" not in txt: txt += " " + next(f).strip()
                    unit = txt.replace("$timescale", "").replace("$end", "").strip()
                    num = int("".join(c for c in unit if c.isdigit()) or "1")
                    u = "".join(c for c in unit if c.isalpha())
                    ts = num * {"fs": 0.001, "ps": 1, "ns": 1000, "us": 10**6}[u]     # ps 단위로
                elif line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    p = line.split()
                    vid, name = p[3], " ".join(p[4:-1])
                    sigs.setdefault(vid, []).append(".".join(scope) + "." + name)
                    width[vid] = int(p[2])
                    changes.setdefault(vid, ([], []))
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            c = line[0]
            if c == "#":
                t = int(line[1:]) * ts
            elif c in "01xXzZ":
                vid = line[1:]
                if vid in changes: changes[vid][0].append(t); changes[vid][1].append(c.lower())
            elif c in "bB":
                v, vid = line[1:].split()
                if vid in changes: changes[vid][0].append(t); changes[vid][1].append(v.lower())
    by_name = {}
    for vid, names in sigs.items():
        for n in names: by_name[n] = (vid, width[vid])
    return by_name, changes

def value_at(ch, t):
    times, vals = ch
    i = bisect.bisect_right(times, t) - 1
    return vals[i] if i >= 0 else "x"

def norm(v, w):
    if len(v) < w: v = (v[0] if v[0] in "xz" else "0") * (w - len(v)) + v
    return v

def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    off = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
    nmax = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
    A, ca = parse(a_path); B, cb = parse(b_path)
    common = sorted(set(A) & set(B))
    tend = min(max((c[0][-1] for c in ca.values() if c[0]), default=0), max((c[0][-1] for c in cb.values() if c[0]), default=0))
    ncyc = min(int((tend - 5000) // 10000), nmax)
    print("signals: A %d, B %d, common %d | clocks compared: %d | B sampled at edge %+.1f ns" % (len(A), len(B), len(common), ncyc, off))
    first = {}     # name -> (cycle, va, vb)
    for n in common:
        (ia, w), (ib, _) = A[n], B[n]
        cha, chb = ca[ia], cb[ib]
        for k in range(1, ncyc):
            edge = 5000 + 10000 * k
            va = norm(value_at(cha, edge - 100), w); vb = norm(value_at(chb, edge + int(off * 1000)), w)
            if va != vb:
                if "x" in va or "z" in va: continue          # A 가 아직 모르는 값이면 비교하지 않음
                first[n] = (k, va, vb); break
    if not first:
        print("NO DIFFERENCE in %d common signals over %d clocks" % (len(common), ncyc)); return 0
    order = sorted(first.items(), key=lambda kv: (kv[1][0], kv[0]))
    k0 = order[0][1][0]
    print("signals that differ: %d of %d. earliest difference at clock %d (pad clock edge at %d ns)" % (len(first), len(common), k0, 5 + 10 * k0))
    for n, (k, va, vb) in order[:60]:
        show = lambda v: v if len(v) <= 34 else v[:16] + ".." + v[-16:]
        print("  clk %5d  %-90s A=%s B=%s" % (k, n[-90:], show(va), show(vb)))
    return 1

if __name__ == "__main__":
    sys.exit(main())
