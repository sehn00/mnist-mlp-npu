"""
gen_golden_10k.py : MNIST 테스트셋 1만 장의 입력 hex + 정답(golden) 생성  (가이드 보고서 6번 "테스트셋 정확도"용)

하는 일
  1) mlp_mnist.pt 를 정수화 (scripts/review/golden_check.py 의 독립 정수화. 팀 hex 와 비트 일치가 확인된 것)
  2) MNIST 테스트셋 1만 장: 픽셀(0~255) >> 1 -> 0~127, 4픽셀씩 한 줄(32b)로 묶기
  3) 먼저 확인: 앞 100장이 지금 data/hex/ 의 100장(입력, label, FC1/FC2/FC3 정답)과 비트 단위로 같은지.
     하나라도 다르면 파일을 쓰지 않고 끝냄 (exit 1)
  4) 1만 장 정수 추론 -> FC1/FC2 출력, FC3 점수, 예측, 정확도
  5) 파일 쓰기 (tb_npu_top 이 읽는 이름 그대로)
       <out>/input_act_a.hex  fc1_out_act_b.hex  fc2_out_act_a196.hex  fc3_omem.hex  labels.txt
       <out>/pred.txt (파이썬 모델의 예측)   reports/accuracy_golden_10k.txt (요약)

MNIST 는 keras 가 받아 둔 mnist.npz (x_test 10000x28x28 uint8, y_test) 를 씀. 다른 위치면 --mnist 로 지정.
  받은 적이 없으면: https://storage.googleapis.com/tensorflow/tf-keras-datasets/mnist.npz (약 11 MB)

사용법 (저장소 루트에서, numpy 만 필요):
  python scripts/gen_golden_10k.py                       # 1만 장 -> build/golden_10k/
  python scripts/gen_golden_10k.py --n 1000 --out build/golden_1k
"""
import argparse, hashlib, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "review"))
from golden_check import load_pt, quantize, read_hex, P, SHIFT, MEAN, STD   # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def pack_lines(M):
    """M: (이미지 수, 4g) 값 0~255 -> 32b 줄 (레인 i -> 비트 [8i+7:8i]) 을 1차원으로"""
    v = M.reshape(M.shape[0], -1, 4).astype(np.uint64) & 0xFF
    return (v[:, :, 0] | (v[:, :, 1] << 8) | (v[:, :, 2] << 16) | (v[:, :, 3] << 24)).ravel()


def write_hex(path, vals):
    with open(path, "w", newline="\n") as f:
        f.write("\n".join("%08x" % int(x) for x in vals) + "\n")


def matmul_exact(x, W):
    # float64 는 2^53 까지 정수를 정확히 표현. 여기 누산값은 최대 2^21 수준이라 결과가 정확함 (BLAS 를 써서 빠름)
    return np.rint(x.astype(np.float64) @ W.T.astype(np.float64)).astype(np.int64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mnist", default=os.path.join(os.path.expanduser("~"), ".keras", "datasets", "mnist.npz"))
    ap.add_argument("--out", default=P("build", "golden_10k"))
    ap.add_argument("--n", type=int, default=10000)
    ap.add_argument("--report", default=P("reports", "accuracy_golden_10k.txt"))
    args = ap.parse_args()

    if not os.path.exists(args.mnist):
        print("MNIST 파일이 없음:", args.mnist)
        print("  --mnist 로 mnist.npz 위치를 주거나, 파일 맨 위 설명의 주소에서 받아 둘 것")
        return 2
    sha = hashlib.sha256(open(args.mnist, "rb").read()).hexdigest()
    d = np.load(args.mnist)
    x_all, y_all = d["x_test"], d["y_test"]
    n = min(args.n, len(x_all))
    px = x_all[:n].reshape(n, 784).astype(np.int64)
    lab = y_all[:n].astype(np.int64)
    q = px >> 1                                           # 0~127
    print("MNIST test set : %d images from %s" % (n, args.mnist))
    print("  sha256 %s" % sha)

    sd = load_pt(P("data", "model", "mlp_mnist.pt"))
    Wq, bq, sw, _, _ = quantize(sd)

    # ---- 정수 추론 (하드웨어와 같은 식: 누산 -> + bias -> ReLU -> >> shift(버림) -> 0~127 포화)
    def post(s, sh):
        r = np.maximum(s, 0) >> sh
        return np.minimum(r, 127), int((r > 127).sum())
    a1 = matmul_exact(q, Wq[0]);  s1 = a1 + bq[0]; h1, sat1 = post(s1, SHIFT[0])
    a2 = matmul_exact(h1, Wq[1]); s2 = a2 + bq[1]; h2, sat2 = post(s2, SHIFT[1])
    a3 = matmul_exact(h2, Wq[2]); s3 = a3 + bq[2]
    for name, v in (("acc1", a1), ("sum1", s1), ("acc2", a2), ("sum2", s2), ("acc3", a3), ("sum3", s3)):
        assert np.abs(v).max() < 2 ** 31, name + " does not fit in int32"
    pred = s3.argmax(axis=1)                              # 같은 점수면 번호가 작은 쪽 (TB 의 argmax 와 같은 규칙)

    in_lines = pack_lines(q)
    fc1_lines = pack_lines(h1)
    fc2_lines = pack_lines(h2)
    fc3_lines = (s3.ravel() & 0xFFFFFFFF)

    # ---- 먼저 확인: 앞 100장이 기존 data/hex/ 와 비트 일치하는지
    print("\n== 기존 golden 100장(data/hex/)과 앞부분 비교")
    m = min(n, 100)
    checks = []
    def cmp(name, mine, path, per):
        ref = read_hex(path)[:m * per]
        mine = [int(v) for v in mine[:m * per]]
        nd = sum(a != b for a, b in zip(mine, ref)) + abs(len(mine) - len(ref))
        checks.append(nd == 0)
        print("  [%s] %-22s %d줄 중 다른 줄 %d" % ("OK  " if nd == 0 else "FAIL", name, len(ref), nd))
    cmp("input_act_a.hex", in_lines, P("data", "hex", "input_act_a.hex"), 196)
    cmp("fc1_out_act_b.hex", fc1_lines, P("data", "hex", "fc1_out_act_b.hex"), 128)
    cmp("fc2_out_act_a196.hex", fc2_lines, P("data", "hex", "fc2_out_act_a196.hex"), 32)
    cmp("fc3_omem.hex", fc3_lines, P("data", "hex", "fc3_omem.hex"), 10)
    ref_lab = [int(s) for s in open(P("data", "hex", "labels.txt")).read().split()][:m]
    nd = sum(int(a) != b for a, b in zip(lab[:m], ref_lab))
    checks.append(nd == 0 and len(ref_lab) == m)
    print("  [%s] %-22s %d개 중 다른 것 %d" % ("OK  " if checks[-1] else "FAIL", "labels.txt", len(ref_lab), nd))
    if not all(checks):
        print("\n앞 100장이 기존 golden 과 다름 -> 파일을 쓰지 않고 끝냄")
        return 1

    # ---- 정확도
    n_ok = int((pred == lab).sum())
    wrong = np.nonzero(pred != lab)[0]
    xf = (px / 255.0 - MEAN) / STD                         # 참고: 정수화 전 float 모델 (float64 로 계산)
    hf = np.maximum(xf @ sd["fc1.weight"].T + sd["fc1.bias"], 0)
    hf = np.maximum(hf @ sd["fc2.weight"].T + sd["fc2.bias"], 0)
    pf = (hf @ sd["fc3.weight"].T + sd["fc3.bias"]).argmax(axis=1)
    n_ok_f = int((pf == lab).sum())
    top2 = np.sort(s3, axis=1)
    n_tie = int((top2[:, -1] == top2[:, -2]).sum())

    # ---- 파일 쓰기
    os.makedirs(args.out, exist_ok=True)
    write_hex(os.path.join(args.out, "input_act_a.hex"), in_lines)
    write_hex(os.path.join(args.out, "fc1_out_act_b.hex"), fc1_lines)
    write_hex(os.path.join(args.out, "fc2_out_act_a196.hex"), fc2_lines)
    write_hex(os.path.join(args.out, "fc3_omem.hex"), fc3_lines)
    for fn, v in (("labels.txt", lab), ("pred.txt", pred)):
        with open(os.path.join(args.out, fn), "w", newline="\n") as f:
            f.write("\n".join("%d" % int(x) for x in v) + "\n")

    rep = []
    rep.append("accuracy_golden_10k : python integer model (scripts/gen_golden_10k.py), golden v2 (shift FC1 %d, FC2 %d)" % SHIFT)
    rep.append("MNIST test set      : %d images, mnist.npz sha256 %s" % (n, sha))
    rep.append("first %d images     : input / label / FC1 / FC2 / FC3 bit-identical to data/hex/ (checked before writing)" % m)
    rep.append("INT  accuracy       : %d / %d = %.2f %%" % (n_ok, n, 100.0 * n_ok / n))
    rep.append("FP   accuracy       : %d / %d = %.2f %%   (float64 model before quantization, for reference)" % (n_ok_f, n, 100.0 * n_ok_f / n))
    rep.append("saturated (>127)    : FC1 %d / %d outputs, FC2 %d / %d outputs" % (sat1, h1.size, sat2, h2.size))
    rep.append("max |acc| FC1/2/3   : %d / %d / %d   (int32 limit 2147483647)" % (np.abs(a1).max(), np.abs(a2).max(), np.abs(a3).max()))
    rep.append("FC3 top-2 ties      : %d images (argmax takes the lower index, same as the testbench)" % n_tie)
    rep.append("output lines        : input %d, FC1 %d, FC2 %d, FC3 %d  -> %s" % (
        len(in_lines), len(fc1_lines), len(fc2_lines), len(fc3_lines), os.path.relpath(args.out, P()).replace(os.sep, "/")))
    rep.append("")
    rep.append("misclassified by the integer model (%d images): image index, predicted -> label" % len(wrong))
    for i in wrong:
        rep.append("  img %5d : pred %d  label %d" % (i, pred[i], lab[i]))
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    with open(args.report, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rep) + "\n")

    print("")
    print("\n".join(rep[:9]))
    print("misclassified: %d images (list in %s)" % (len(wrong), os.path.relpath(args.report, P()).replace(os.sep, "/")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
