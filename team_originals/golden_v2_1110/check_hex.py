"""
check_hex.py : hex 파일만 읽어서 하드웨어 순서대로 한 장을 다시 계산하고
               golden_fc*.hex 와 비트 단위로 비교 (레이아웃 검증용)
사용법: python check_hex.py --dir ./out --img 0 --s1 11 --s2 7
"""
import argparse, os


def s8(v):  return v - 256 if v & 0x80 else v
def s32(v): return v - (1 << 32) if v & 0x80000000 else v
def read(path): return [int(l, 16) for l in open(path) if l.strip()]
def unpack(w): return [s8((w >> (8 * i)) & 0xFF) for i in range(4)]
def pack(vals): return sum((v & 0xFF) << (8 * i) for i, v in enumerate(vals))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="./out")
    ap.add_argument("--img", type=int, default=0)
    ap.add_argument("--s1", type=int, required=True)
    ap.add_argument("--s2", type=int, required=True)
    a = ap.parse_args()
    tag = f"{a.img:04d}"
    wmem = read(os.path.join(a.dir, "weight.hex"))
    bias = [s32(v) for v in read(os.path.join(a.dir, "bias.hex"))]
    act_in = read(os.path.join(a.dir, f"input_{tag}.hex"))

    # (K, 뉴런 수, WMEM base, BIAS base, shift)
    layers = [(784, 512, 0, 0, a.s1), (512, 128, 100352, 512, a.s2), (128, 10, 116736, 640, None)]
    act = act_in
    outs = []
    for K, N, wbase, bbase, sh in layers:
        res = []
        for n in range(N):
            acc = 0
            for g in range(K // 4):
                w = unpack(wmem[wbase + n * (K // 4) + g])
                x = unpack(act[g])
                acc += sum(xi * wi for xi, wi in zip(x, w))   # 곱셈 4개 + 덧셈 트리
            y = acc + bias[bbase + n]
            if sh is not None:
                y = min(max(y, 0) >> sh, 127)
            res.append(y)
        if sh is not None:
            act = [pack(res[4 * g:4 * g + 4]) for g in range(N // 4)]
        outs.append((res, act))

    ok = True
    for k, name in ((0, "fc1"), (1, "fc2")):
        gold = read(os.path.join(a.dir, f"golden_{name}_{tag}.hex"))
        same = gold == outs[k][1]
        ok &= same
        print(f"{name}: {'일치' if same else '불일치'} ({len(gold)}줄)")
    gold3 = [s32(v) for v in read(os.path.join(a.dir, f"golden_fc3_{tag}.hex"))]
    same = gold3 == outs[2][0]
    ok &= same
    print(f"fc3: {'일치' if same else '불일치'} ({len(gold3)}줄), pred = {gold3.index(max(gold3))}")
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()
