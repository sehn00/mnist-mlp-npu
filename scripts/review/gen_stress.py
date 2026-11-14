"""
gen_stress.py : 합성(가짜) 입력 이미지 세트 + 정답 생성 (리뷰용)

왜: golden 사진 100장에서는 FC1/FC2 출력이 한 번도 127 을 넘지 않아서(golden_check.py 출력 참고)
    A 블록의 포화(0~127 clamp) 회로와 큰 누산값이 통합 TB 에서 한 번도 시험되지 않는다.
    그래서 극단적인 입력을 만들어 같은 tb_npu_top 으로 돌린다. 정답은 golden_check.py 와 같은
    독립 정수 모델(.pt 에서 직접 정수화)로 계산한다.

만드는 이미지 (전부 픽셀 값 0~127)
  0 전부 0                     1 전부 127
  2 FC1 에서 합이 가장 커지는 뉴런을 최대로 만드는 입력 (w > 0 인 자리만 127)
  3 같은 뉴런을 최소로 만드는 입력 (w < 0 인 자리만 127)
  4~7 레인 j (j = 0..3) 자리만 값이 있고 나머지는 0  -> 레인 순서가 바뀌면 바로 틀림
  8 체커보드(0/127)            9 줄 번호 k 를 그대로 값으로 (주소 순서 확인용)
  10~15 난수 (고정 seed), 뒤로 갈수록 밝게

출력: build/review/stress_hex/  (tb_npu_top 이 읽는 5개 파일 + 체커용 rev_*.hex)
사용법: python scripts/review/gen_stress.py
        HEX_SRC=build/review/stress_hex STAGE_SRC=build/review/stress_hex \
          scripts/review/xrun.sh stress rtl "N_IMG=16 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from golden_check import load_pt, quantize, pack4, u32, P, SHIFT

def main():
    sd = load_pt(P("team_originals", "golden_v2_1110", "mlp_mnist.pt"))
    Wq, bq, sw, _, _ = quantize(sd)
    rs = np.random.RandomState(20261114)
    imgs = []
    imgs.append(np.zeros(784, dtype=np.int64))
    imgs.append(np.full(784, 127, dtype=np.int64))
    pos = np.where(Wq[0] > 0, Wq[0], 0).sum(axis=1) * 127 + bq[0]
    n_star = int(np.argmax(pos))
    imgs.append(np.where(Wq[0][n_star] > 0, 127, 0).astype(np.int64))
    imgs.append(np.where(Wq[0][n_star] < 0, 127, 0).astype(np.int64))
    for j in range(4):
        v = np.zeros(784, dtype=np.int64); v[j::4] = rs.randint(0, 128, size=196); imgs.append(v)
    imgs.append(((np.arange(784) // 28 + np.arange(784) % 28) % 2 * 127).astype(np.int64))
    imgs.append((np.arange(784) // 4 % 128).astype(np.int64))
    for hi in (16, 32, 64, 96, 128, 128):
        imgs.append(rs.randint(0, hi, size=784).astype(np.int64))
    X = np.stack(imgs)

    def post(s, sh):
        r = np.maximum(s, 0) >> sh
        return np.minimum(r, 127), int((r > 127).sum())

    a1 = X @ Wq[0].T;  s1 = a1 + bq[0]; h1, sat1 = post(s1, SHIFT[0])
    a2 = h1 @ Wq[1].T; s2 = a2 + bq[1]; h2, sat2 = post(s2, SHIFT[1])
    a3 = h2 @ Wq[2].T; s3 = a3 + bq[2]
    for name, v in (("acc1", a1), ("sum1", s1), ("acc2", a2), ("sum2", s2), ("acc3", a3), ("sum3", s3)):
        assert np.abs(v).max() < 2 ** 31, name + " overflow"

    out = P("build", "review", "stress_hex"); os.makedirs(out, exist_ok=True)
    def wr(fn, lines):
        with open(os.path.join(out, fn), "w") as f: f.write("\n".join(lines) + "\n")
    packed = lambda M: ["%08x" % pack4(row[4 * g:4 * g + 4]) for row in M for g in range(len(row) // 4)]
    wr("input_act_a.hex", packed(X))
    wr("fc1_out_act_b.hex", packed(h1))
    wr("fc2_out_act_a196.hex", packed(h2))
    wr("fc3_omem.hex", ["%08x" % u32(v) for row in s3 for v in row])
    wr("labels.txt", ["%d" % int(np.argmax(row)) for row in s3])      # "정답" 대신 모델의 예측을 넣음 (TB 의 예측 비교용)
    for name, v in (("acc1", a1), ("sum1", s1), ("acc2", a2), ("sum2", s2), ("acc3", a3), ("sum3", s3)):
        wr("rev_%s.hex" % name, ["%08x" % u32(x) for row in v for x in row])

    print("stress images       : %d  -> %s" % (len(imgs), out))
    print("FC1 saturated (>127): %d / %d outputs,  FC2 saturated: %d / %d" % (sat1, h1.size, sat2, h2.size))
    print("max |acc| FC1/2/3   : %d / %d / %d" % (np.abs(a1).max(), np.abs(a2).max(), np.abs(a3).max()))
    print("per image FC1 sat   :", [int(((np.maximum(s, 0) >> SHIFT[0]) > 127).sum()) for s in s1])
    print("per image FC2 sat   :", [int(((np.maximum(s, 0) >> SHIFT[1]) > 127).sum()) for s in s2])
    print("FC3 score range     : %d .. %d" % (s3.min(), s3.max()))

if __name__ == "__main__":
    main()
