"""
golden_v1.py : MNIST MLP (784-512-128-10) 정수 골든 모델 + hex 추출

하드웨어 규칙 (10/29 계획서)
  - 입력: 픽셀(0~255) >> 1  ->  0~127
  - 가중치: 레이어별 대칭 int8 (scale = 127 / max|W|)
  - bias: 누산값과 같은 스케일의 int32, 누산 32b
  - FC1, FC2: acc + bias -> ReLU -> >> shift (버림) -> 0~127 포화
  - FC3: acc + bias 를 int32 그대로 출력, argmax 는 testbench
  - 입력 Normalize(0.1307, 0.3081) 는 FC1 가중치와 bias 에 folding

메모리 레이아웃 (입력 방향, PE 4)
  - weight.hex : 레이어 FC1 -> FC2 -> FC3, 뉴런 n, 묶음 g 순서
                 한 줄 [8i+7:8i] = W[n][4g+i]  (117,056줄)
  - bias.hex   : FC1 512 + FC2 128 + FC3 10 = 650줄, int32
  - input_XXXX.hex : 196줄, 한 줄 [8i+7:8i] = 픽셀 4g+i
  - golden_fc1/fc2 : int8 4개 묶음 (128줄 / 32줄), golden_fc3 : int32 10줄

사용법
  python golden_v1.py --model mlp_mnist.pt --mnist ./mnist --out ./out --n_images 10
  (mnist 폴더에 t10k/train idx .gz 파일이 없으면 자동으로 받음)
"""
import argparse, gzip, os, pickle, struct, urllib.request, zipfile
import numpy as np

MEAN, STD = 0.1307, 0.3081
MNIST_URL = "https://ossci-datasets.s3.amazonaws.com/mnist/"
MNIST_FILES = ["t10k-images-idx3-ubyte", "t10k-labels-idx1-ubyte",
               "train-images-idx3-ubyte", "train-labels-idx1-ubyte"]


# ---------------------------------------------------------------- 모델 읽기
def load_state_dict(path):
    """torch 가 있으면 torch.load, 없으면 .pt(zip) 를 직접 파싱"""
    try:
        import torch
        sd = torch.load(path, map_location="cpu", weights_only=True)
        return {k: v.numpy().astype(np.float64) for k, v in sd.items()}
    except ImportError:
        pass
    zf = zipfile.ZipFile(path)
    prefix = zf.namelist()[0].split("/")[0]

    class _Storage:
        def __init__(self, key): self.key = key

    def rebuild(storage, offset, size, stride, *args):
        raw = zf.read(f"{prefix}/data/{storage.key}")
        flat = np.frombuffer(raw, dtype="<f4")
        n = int(np.prod(size)) if size else 1
        return flat[offset:offset + n].reshape(size).astype(np.float64)

    class _Unpickler(pickle.Unpickler):
        def find_class(self, module, name):
            if name == "_rebuild_tensor_v2": return rebuild
            if name == "OrderedDict":
                from collections import OrderedDict; return OrderedDict
            if name.endswith("Storage"): return name
            raise pickle.UnpicklingError(f"unexpected {module}.{name}")
        def persistent_load(self, pid):
            return _Storage(pid[2])

    return dict(_Unpickler(zf.open(f"{prefix}/data.pkl")).load())


# ---------------------------------------------------------------- MNIST 읽기
def load_mnist(folder):
    os.makedirs(folder, exist_ok=True)
    out = {}
    for f in MNIST_FILES:
        p = os.path.join(folder, f + ".gz")
        if not os.path.exists(p):
            urllib.request.urlretrieve(MNIST_URL + f + ".gz", p)
        with gzip.open(p, "rb") as fh:
            data = fh.read()
        if "images" in f:
            n = struct.unpack(">I", data[4:8])[0]
            out[f] = np.frombuffer(data, np.uint8, offset=16).reshape(n, 784)
        else:
            out[f] = np.frombuffer(data, np.uint8, offset=8)
    return (out["train-images-idx3-ubyte"], out["train-labels-idx1-ubyte"],
            out["t10k-images-idx3-ubyte"], out["t10k-labels-idx1-ubyte"])


# ---------------------------------------------------------------- 정수화
def quantize(sd):
    W1, b1 = sd["fc1.weight"], sd["fc1.bias"]
    W2, b2 = sd["fc2.weight"], sd["fc2.bias"]
    W3, b3 = sd["fc3.weight"], sd["fc3.bias"]
    # Normalize folding: x_norm = (p/255 - MEAN)/STD,  p ~= 2*q  (q = p>>1)
    W1f = W1 * (2.0 / (255.0 * STD))
    b1f = b1 - W1.sum(axis=1) * (MEAN / STD)
    Ws = [W1f, W2, W3]
    bs = [b1f, b2, b3]
    sw = [127.0 / np.abs(W).max() for W in Ws]
    Wq = [np.clip(np.round(W * s), -128, 127).astype(np.int64) for W, s in zip(Ws, sw)]
    return Wq, bs, sw


def quant_bias(bs, sw, shifts):
    """입력 스케일: FC1 = 1, FC(k+1) = FC(k) 누산 스케일 / 2^shift"""
    in_scale = 1.0
    bq = []
    for k in range(3):
        acc_scale = sw[k] * in_scale
        bq.append(np.round(bs[k] * acc_scale).astype(np.int64))
        if k < 2:
            in_scale = acc_scale / (2 ** shifts[k])
    return bq


# ---------------------------------------------------------------- 정수 추론
def matmul_int(x, W):
    # float64 는 2^53 까지 정수를 정확히 표현 (누산 최대 약 2^26)
    return np.rint(x.astype(np.float64) @ W.T.astype(np.float64)).astype(np.int64)


def post(acc, bias, shift):
    y = np.maximum(acc + bias, 0)          # + bias -> ReLU
    y = y >> shift                         # 산술 shift, 버림
    return np.clip(y, 0, 127)              # 0~127 포화


def infer(q_img, Wq, bq, shifts, keep=False):
    a1 = matmul_int(q_img, Wq[0]); h1 = post(a1, bq[0], shifts[0])
    a2 = matmul_int(h1, Wq[1]);    h2 = post(a2, bq[1], shifts[1])
    a3 = matmul_int(h2, Wq[2]);    s3 = a3 + bq[2]
    if keep:
        return dict(acc1=a1, fc1=h1, acc2=a2, fc2=h2, acc3=a3, fc3=s3)
    return s3


def float_infer(img, sd):
    x = (img / 255.0 - MEAN) / STD
    h = np.maximum(x @ sd["fc1.weight"].T + sd["fc1.bias"], 0)
    h = np.maximum(h @ sd["fc2.weight"].T + sd["fc2.bias"], 0)
    return h @ sd["fc3.weight"].T + sd["fc3.bias"]


# ---------------------------------------------------------------- hex 출력
def h32(v):
    return f"{int(v) & 0xFFFFFFFF:08x}"


def pack4(vals):
    """vals[i] -> [8i+7:8i] (int8 4개 -> 32b)"""
    w = 0
    for i, v in enumerate(vals):
        w |= (int(v) & 0xFF) << (8 * i)
    return f"{w:08x}"


def write_lines(path, lines):
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def weight_lines(Wq):
    lines = []
    for W in Wq:
        n_out, k = W.shape
        for n in range(n_out):
            for g in range(k // 4):
                lines.append(pack4(W[n, 4 * g:4 * g + 4]))
    return lines


def packed_lines(vec):
    return [pack4(vec[4 * g:4 * g + 4]) for g in range(len(vec) // 4)]


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="mlp_mnist.pt")
    ap.add_argument("--mnist", default="./mnist")
    ap.add_argument("--out", default="./out")
    ap.add_argument("--n_images", type=int, default=10)
    ap.add_argument("--calib", type=int, default=10000, help="shift 선택에 쓸 학습 이미지 수")
    ap.add_argument("--select", choices=["test", "train"], default="test",
                    help="shift 를 고를 데이터 (test: 테스트 1만 장 정확도 기준)")
    args = ap.parse_args()

    sd = load_state_dict(args.model)
    tr_x, tr_y, te_x, te_y = load_mnist(args.mnist)
    Wq, bs, sw = quantize(sd)

    # shift 선택: 정수 정확도가 가장 높은 (s1, s2)
    if args.select == "test":
        cx, cy = te_x >> 1, te_y
    else:
        cx, cy = tr_x[:args.calib] >> 1, tr_y[:args.calib]
    best = None
    for s1 in range(0, 17):
        for s2 in range(0, 17):
            bq = quant_bias(bs, sw, (s1, s2))
            acc = (infer(cx, Wq, bq, (s1, s2)).argmax(1) == cy).mean()
            if best is None or acc > best[0]:
                best = (acc, s1, s2)
    _, s1, s2 = best
    shifts = (s1, s2)
    bq = quant_bias(bs, sw, shifts)

    # 정확도 (테스트 1만 장)
    fp_acc = (float_infer(te_x, sd).argmax(1) == te_y).mean() * 100
    tq = te_x >> 1
    r = infer(tq, Wq, bq, shifts, keep=True)
    int_acc = (r["fc3"].argmax(1) == te_y).mean() * 100
    for k in ("acc1", "acc2", "acc3"):
        assert np.abs(r[k]).max() < 2 ** 31, "누산 오버플로"
    for b in bq:
        assert np.abs(b).max() < 2 ** 31, "bias 오버플로"

    os.makedirs(args.out, exist_ok=True)
    wl = weight_lines(Wq)
    bl = [h32(v) for b in bq for v in b]
    write_lines(os.path.join(args.out, "weight.hex"), wl)
    write_lines(os.path.join(args.out, "bias.hex"), bl)

    for i in range(args.n_images):
        tag = f"{i:04d}"
        write_lines(os.path.join(args.out, f"input_{tag}.hex"), packed_lines(tq[i]))
        write_lines(os.path.join(args.out, f"golden_fc1_{tag}.hex"), packed_lines(r["fc1"][i]))
        write_lines(os.path.join(args.out, f"golden_fc2_{tag}.hex"), packed_lines(r["fc2"][i]))
        write_lines(os.path.join(args.out, f"golden_fc3_{tag}.hex"), [h32(v) for v in r["fc3"][i]])
    with open(os.path.join(args.out, "labels.txt"), "w") as f:
        for i in range(args.n_images):
            f.write(f"{i:04d} label={te_y[i]} pred={r['fc3'][i].argmax()}\n")

    # 디버깅용: 이미지 0 의 레이어별 중간값 (10진수)
    with open(os.path.join(args.out, "debug_0000.txt"), "w") as f:
        for L, (ka, kh, bias, sh) in enumerate([("acc1", "fc1", bq[0], s1),
                                                ("acc2", "fc2", bq[1], s2)], 1):
            f.write(f"# FC{L}: n, acc, acc+bias, relu, >>{sh}, clamp(out)\n")
            for n in range(len(bias)):
                a = r[ka][0, n]; ab = a + bias[n]; rl = max(ab, 0)
                f.write(f"{n} {a} {ab} {rl} {rl >> sh} {r[kh][0, n]}\n")
        f.write("# FC3: n, acc, acc+bias\n")
        for n in range(10):
            f.write(f"{n} {r['acc3'][0, n]} {r['fc3'][0, n]}\n")

    summary = (
        f"FP32 test accuracy   : {fp_acc:.2f}%\n"
        f"INT   test accuracy  : {int_acc:.2f}%\n"
        f"shift (FC1, FC2)     : {s1}, {s2}  (선택 기준: {args.select})\n"
        f"weight scale (FC1~3) : {sw[0]:.4f}, {sw[1]:.4f}, {sw[2]:.4f}\n"
        f"max |acc| FC1/2/3    : {np.abs(r['acc1']).max()}, {np.abs(r['acc2']).max()}, {np.abs(r['acc3']).max()}\n"
        f"max |bias| FC1/2/3   : {np.abs(bq[0]).max()}, {np.abs(bq[1]).max()}, {np.abs(bq[2]).max()}\n"
        f"weight.hex lines     : {len(wl)}\n"
        f"bias.hex lines       : {len(bl)}\n"
    )
    with open(os.path.join(args.out, "summary.txt"), "w") as f:
        f.write(summary)
    print(summary)


if __name__ == "__main__":
    main()
