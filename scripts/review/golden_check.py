"""
golden_check.py : 골든 독립 확인 (리뷰 1단계 4번)

팀의 golden_v1.py 를 쓰지 않고, mlp_mnist.pt 에서 직접
  (1) 가중치/bias 정수화  (2) 하드웨어 순서(줄 단위, 레인 4개) 정수 추론
을 다시 계산해서 팀 파일과 비트 단위로 비교한다.

비교 대상
  A. 가중치  : golden/mem/wmem.hex(단일 117,056줄), coe/weight_bank0~3.coe(4뱅크), hex/weight_bank*.mem
  B. bias    : golden/mem/bias.hex(650줄), coe/bias_128bit.coe(128b x 163), hex/bias_128bit.mem
  C. 추론 결과: hex/fc1_out_act_b.hex, fc2_out_act_a196.hex, fc3_omem.hex (사진 100장), labels.txt
  D. 단계별   : handoff_D_1112/golden/stages/* (사진 0~9)
그리고 비트 폭 확인(곱 s16, 덧셈 s17/s18, 누산 s32)과, 체커 TB 가 쓸 단계별 정답(100장)을 build/review/golden_stages/ 에 쓴다.

입력 사진은 hex/input_act_a.hex(이미 0~127 로 바꾼 값)를 그대로 쓴다.
MNIST 원본이 이 PC 에 없어서 "픽셀 >> 1" 변환 자체는 여기서 확인하지 못한다.

사용법: python scripts/review/golden_check.py     (저장소 루트에서, numpy 만 필요)
"""
import os, sys, zipfile, pickle
from collections import OrderedDict
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
P = lambda *a: os.path.join(ROOT, *a)
MEAN, STD = 0.1307, 0.3081            # torchvision MNIST Normalize 값 (팀 계획서와 같음)
SHIFT = (11, 7)                        # golden v2
LAYERS = [(196, 512), (128, 128), (32, 10)]   # (L = 입력 줄 수, N = 뉴런 수)
W_BASE = [0, 100352, 116736]
B_BASE = [0, 512, 640]
WB_BASE = [0, 25088, 29184]

results = []                           # (이름, 통과 여부, 설명)
def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("  [OK]   " if ok else "  [FAIL] ") + name + (" : " + detail if detail else ""))


# ---------------------------------------------------------------- 1. .pt 읽기 (torch 없이)
def load_pt(path):
    zf = zipfile.ZipFile(path)
    pkl = [n for n in zf.namelist() if n.endswith("data.pkl")][0]
    prefix = pkl[:-len("data.pkl")]
    dtypes = {"FloatStorage": "<f4", "DoubleStorage": "<f8", "LongStorage": "<i8", "IntStorage": "<i4"}

    def rebuild_tensor(storage, offset, size, stride, *rest):
        key, dt = storage
        flat = np.frombuffer(zf.read(prefix + "data/" + key), dtype=dt)
        n = int(np.prod(size)) if len(size) else 1
        return flat[offset:offset + n].reshape(tuple(size)).astype(np.float64)

    class U(pickle.Unpickler):
        def find_class(self, module, name):
            if module == "collections" and name == "OrderedDict": return OrderedDict
            if name == "_rebuild_tensor_v2": return rebuild_tensor
            if name in dtypes: return dtypes[name]
            raise pickle.UnpicklingError("unexpected global %s.%s" % (module, name))
        def persistent_load(self, pid):          # ('storage', 저장 타입, key, 위치, 원소 수)
            return (pid[2], pid[1])
    return dict(U(zf.open(pkl)).load())


# ---------------------------------------------------------------- 2. 정수화
def quantize(sd):
    W = [sd["fc1.weight"], sd["fc2.weight"], sd["fc3.weight"]]
    b = [sd["fc1.bias"], sd["fc2.bias"], sd["fc3.bias"]]
    # 입력 q = 픽셀 >> 1 (0~127) 이므로 픽셀 ~= 2q.  x_norm = (픽셀/255 - MEAN)/STD = q * 2/(255*STD) - MEAN/STD
    # -> FC1 을 q 기준으로 다시 쓰면  W1' = W1 * 2/(255*STD),  b1' = b1 - sum_j(W1[:,j]) * MEAN/STD
    b = [b[0] - W[0].sum(axis=1) * (MEAN / STD), b[1], b[2]]
    W = [W[0] * (2.0 / (255.0 * STD)), W[1], W[2]]
    sw = [127.0 / np.abs(w).max() for w in W]                       # 레이어별 대칭 int8 스케일
    scaled = [w * s for w, s in zip(W, sw)]
    tie = min(np.abs(np.abs(x - np.floor(x)) - 0.5).min() for x in scaled)
    Wq = [np.rint(x).astype(np.int64) for x in scaled]
    bq, in_scale, btie = [], 1.0, 1.0
    for k in range(3):
        acc_scale = sw[k] * in_scale                                  # 누산기 스케일 = 가중치 스케일 x 입력 스케일
        v = b[k] * acc_scale
        btie = min(btie, np.abs(np.abs(v - np.floor(v)) - 0.5).min())
        bq.append(np.rint(v).astype(np.int64))
        if k < 2: in_scale = acc_scale / (2 ** SHIFT[k])              # 다음 레이어 입력 스케일
    return Wq, bq, sw, tie, btie


# ---------------------------------------------------------------- 파일 읽기 도구
def read_hex(path, coe=False):
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip().rstrip(",;")
            if not s or (coe and ("=" in s)): continue
            out.append(int(s, 16))
    return out

def pack4(v):                       # 레인 i -> 비트 [8i+7:8i]
    return sum((int(x) & 0xFF) << (8 * i) for i, x in enumerate(v))

def s8(x):  return x - 256 if x & 0x80 else x
def u32(x): return int(x) & 0xFFFFFFFF


def main():
    sd = load_pt(P("team_originals", "golden_v2_1110", "mlp_mnist.pt"))
    print("model tensors:", {k: v.shape for k, v in sd.items()})
    Wq, bq, sw, tie, btie = quantize(sd)
    print("weight scale FC1/2/3 : %.4f, %.4f, %.4f" % tuple(sw))
    print("round() 경계(.5)까지 가장 가까운 거리: weight %.3g, bias %.3g  (0 에 가까우면 반올림 방식에 따라 값이 갈림)" % (tie, btie))

    print("\n== A. 가중치")
    for k in range(3):
        check("FC%d 가중치 범위 -127~127" % (k + 1), Wq[k].min() >= -127 and Wq[k].max() <= 127,
              "min %d max %d" % (Wq[k].min(), Wq[k].max()))
    mine = []
    for k, (L, N) in enumerate(LAYERS):
        for n in range(N):
            for g in range(L):
                mine.append(pack4(Wq[k][n, 4 * g:4 * g + 4]))
    team_w = read_hex(P("team_originals", "handoff_D_1112", "golden", "mem", "wmem.hex"))
    nd = sum(a != b for a, b in zip(mine, team_w))
    check("내 정수화 == handoff wmem.hex (117,056줄)", len(mine) == len(team_w) == 117056 and nd == 0, "다른 줄 %d" % nd)
    v2_w = read_hex(P("team_originals", "golden_v2_1110", "out", "weight.hex"))
    check("handoff wmem.hex == golden_v2 weight.hex", v2_w == team_w)
    # 4뱅크: 뱅크 i 의 주소 wbank_base + (n//4)*L + k  <->  단일 주소 w_base + n*L + k  (n%4 == i)
    banks = [read_hex(P("coe", "weight_bank%d.coe" % i), coe=True) for i in range(4)]
    check("COE 뱅크 4개 깊이 29,280", all(len(b) == 29280 for b in banks), str([len(b) for b in banks]))
    bad, used = 0, [set() for _ in range(4)]
    for k, (L, N) in enumerate(LAYERS):
        for n in range(N):
            for g in range(L):
                a = WB_BASE[k] + (n // 4) * L + g
                used[n % 4].add(a)
                if banks[n % 4][a] != mine[W_BASE[k] + n * L + g]: bad += 1
    check("COE 4뱅크 내용 == 내 정수화 (D 의 주소 매핑 식으로 117,056줄 전부)", bad == 0, "다른 줄 %d" % bad)
    pad = [(i, a, banks[i][a]) for i in range(4) for a in range(29280) if a not in used[i]]
    check("안 쓰는 뱅크 주소(FC3 뉴런 10, 11 자리)는 0", all(v == 0 for _, _, v in pad),
          "안 쓰는 주소 %d개 (뱅크 2, 3 의 29,248~29,279)" % len(pad))
    for i in range(4):
        check("hex/weight_bank%d.mem == COE" % i, read_hex(P("hex", "weight_bank%d.mem" % i)) == banks[i])

    print("\n== B. bias")
    mine_b = [u32(v) for k in range(3) for v in bq[k]]
    team_b = read_hex(P("team_originals", "handoff_D_1112", "golden", "mem", "bias.hex"))
    nd = sum(a != b for a, b in zip(mine_b, team_b))
    check("내 bias == handoff bias.hex (650줄)", len(mine_b) == len(team_b) == 650 and nd == 0, "다른 줄 %d" % nd)
    check("handoff bias.hex == golden_v2 bias.hex", read_hex(P("team_originals", "golden_v2_1110", "out", "bias.hex")) == team_b)
    b128 = read_hex(P("coe", "bias_128bit.coe"), coe=True)
    exp128 = []
    for m in range(163):
        v = 0
        for j in range(4):
            idx = 4 * m + j
            v |= (mine_b[idx] if idx < 650 else 0) << (32 * j)        # [31:0] = bias 4m, ... [127:96] = bias 4m+3
        exp128.append(v)
    check("COE bias_128bit (128b x 163) == 내 bias 4개 묶음", b128 == exp128,
          "다른 줄 %d" % sum(a != b for a, b in zip(b128, exp128)))
    check("hex/bias_128bit.mem == COE", read_hex(P("hex", "bias_128bit.mem")) == b128)

    print("\n== C. 정수 추론 (하드웨어 순서) : 사진 100장")
    xin = read_hex(P("hex", "input_act_a.hex"))
    n_img = len(xin) // 196
    g1 = read_hex(P("hex", "fc1_out_act_b.hex")); g2 = read_hex(P("hex", "fc2_out_act_a196.hex"))
    g3 = read_hex(P("hex", "fc3_omem.hex"));      lab = [int(s) for s in open(P("hex", "labels.txt")).read().split()]
    check("입력 100장 x 196줄, 모든 값 0~127", n_img == 100 and all(((w >> (8 * i)) & 0xFF) <= 127 for w in xin for i in range(4)))

    W4 = [Wq[k].reshape(N, L, 4) for k, (L, N) in enumerate(LAYERS)]   # [뉴런][줄][레인]
    rng = dict(prod=0, s17=0, s18=0, acc=0, sum=0)
    stage = {k: [] for k in ("acc1", "sum1", "acc2", "sum2", "acc3", "sum3")}
    bad1 = bad2 = bad3 = n_ok = 0
    sat_cnt = [0, 0]; act_cnt = [0, 0]

    def layer(x_lines, k):
        """x_lines: 32b 줄 리스트(L개). 반환: (acc[N], sum[N]). 줄 단위로 곱 4개 -> 덧셈 트리 -> 누산"""
        L, N = LAYERS[k]
        x = np.array([[s8((w >> (8 * i)) & 0xFF) for i in range(4)] for w in x_lines], dtype=np.int64)   # C 는 x 도 signed 로 해석
        p = W4[k] * x[None, :, :]                       # 곱 4개 (s16)
        s01 = p[:, :, 0] + p[:, :, 1]; s23 = p[:, :, 2] + p[:, :, 3]   # 덧셈 1단 (s17)
        s = s01 + s23                                   # 덧셈 2단 (s18)
        run = np.cumsum(s, axis=1)                      # 누산기의 매 클럭 값 (s32)
        rng["prod"] = max(rng["prod"], int(np.abs(p).max())); rng["s17"] = max(rng["s17"], int(np.abs(s01).max()), int(np.abs(s23).max()))
        rng["s18"] = max(rng["s18"], int(np.abs(s).max()));   rng["acc"] = max(rng["acc"], int(np.abs(run).max()))
        acc = run[:, -1]
        sm = acc + bq[k]
        rng["sum"] = max(rng["sum"], int(np.abs(sm).max()))
        return acc, sm

    def post(sm, sh, k):
        r = np.maximum(sm, 0) >> sh                     # ReLU -> 산술 오른쪽 shift(버림)
        sat_cnt[k] += int((r > 127).sum()); act_cnt[k] += r.size
        y = np.minimum(r, 127)                          # 0~127 포화
        return [pack4(y[4 * g:4 * g + 4]) for g in range(len(y) // 4)]

    for im in range(n_img):
        a1, s1 = layer(xin[im * 196:(im + 1) * 196], 0); o1 = post(s1, SHIFT[0], 0)
        a2, s2 = layer(o1, 1);                           o2 = post(s2, SHIFT[1], 1)
        a3, s3 = layer(o2, 2);                           o3 = [u32(v) for v in s3]
        bad1 += sum(a != b for a, b in zip(o1, g1[im * 128:(im + 1) * 128]))
        bad2 += sum(a != b for a, b in zip(o2, g2[im * 32:(im + 1) * 32]))
        bad3 += sum(a != b for a, b in zip(o3, g3[im * 10:(im + 1) * 10]))
        n_ok += int(int(np.argmax(s3)) == lab[im])
        for key, v in (("acc1", a1), ("sum1", s1), ("acc2", a2), ("sum2", s2), ("acc3", a3), ("sum3", s3)):
            stage[key].extend(u32(x) for x in v)
    check("FC1 출력 100장 x 128줄 == golden", bad1 == 0, "다른 줄 %d / %d" % (bad1, len(g1)))
    check("FC2 출력 100장 x 32줄 == golden", bad2 == 0, "다른 줄 %d / %d" % (bad2, len(g2)))
    check("FC3 점수 100장 x 10줄 == golden", bad3 == 0, "다른 줄 %d / %d" % (bad3, len(g3)))
    check("예측(argmax) == labels.txt", n_ok == n_img, "%d / %d" % (n_ok, n_img))
    print("  포화(>127)된 출력: FC1 %d / %d, FC2 %d / %d" % (sat_cnt[0], act_cnt[0], sat_cnt[1], act_cnt[1]))

    print("\n== 비트 폭 (사진 100장에서 나온 최대 절댓값)")
    check("곱 s16 (|p| <= 32,767)", rng["prod"] <= 32767, "max |p| = %d" % rng["prod"])
    check("덧셈 1단 s17 (<= 65,535)", rng["s17"] <= 65535, "max = %d" % rng["s17"])
    check("덧셈 2단 s18 (<= 131,071)", rng["s18"] <= 131071, "max = %d" % rng["s18"])
    check("누산 s32 (매 클럭 값 포함)", rng["acc"] < 2 ** 31, "max |acc| = %d (2^%.1f)" % (rng["acc"], np.log2(max(rng["acc"], 1))))
    check("acc + bias s32", rng["sum"] < 2 ** 31, "max = %d" % rng["sum"])
    # 최악의 경우(입력 전부 127, 가중치 부호가 전부 같은 쪽)에도 32b 안인지: 실제 가중치로 계산
    worst = max(int(np.abs(Wq[k]).sum(axis=1).max()) * 127 + int(np.abs(bq[k]).max()) for k in range(3))
    check("최악 입력에서도 s32 안 (실제 가중치 기준 상한)", worst < 2 ** 31, "상한 %d (2^%.1f)" % (worst, np.log2(worst)))

    print("\n== D. 단계별 정답 (사진 0~9, handoff stages)")
    st = P("team_originals", "handoff_D_1112", "golden", "stages")
    for key, fn, per in (("acc1", "fc1_1_acc_nobias.hex", 512), ("sum1", "fc1_2_plus_bias.hex", 512),
                         ("acc2", "fc2_1_acc_nobias.hex", 128), ("sum2", "fc2_2_plus_bias.hex", 128),
                         ("acc3", "fc3_1_acc_nobias.hex", 10),  ("sum3", "fc3_2_plus_bias.hex", 10)):
        t = read_hex(os.path.join(st, fn))
        check("%s == 내 계산 (10장 x %d)" % (fn, per), t == stage[key][:len(t)] and len(t) == 10 * per)

    out = P("build", "review", "golden_stages"); os.makedirs(out, exist_ok=True)
    for key, v in stage.items():
        with open(os.path.join(out, "rev_%s.hex" % key), "w") as f:
            f.write("\n".join("%08x" % x for x in v) + "\n")
    print("\n체커용 단계별 정답(100장) -> build/review/golden_stages/rev_*.hex")

    nfail = sum(1 for _, ok, _ in results if not ok)
    print("\n==== golden_check: %d checks, %d FAIL ====" % (len(results), nfail))
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
