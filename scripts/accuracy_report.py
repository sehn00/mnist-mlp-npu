"""
accuracy_report.py : scripts/run_accuracy.sh 가 남긴 묶음 로그를 모아 테스트셋 정확도 요약을 씀

읽는 것
  <chunks>/chunk_*.log  tb_npu_top (ACC_ONLY) 출력. 이미지마다 한 줄:
                        img 123 : FC3 10/10 match | pred 7 label 7 | 119009 clk | PASS
  <gold>/labels.txt     정답 숫자,  <gold>/pred.txt  파이썬 정수 모델의 예측
쓰는 것
  --out (기본 reports/accuracy_10k.txt)
반환값: 0 = 이미지가 빠짐없이 한 번씩 있고, 전부 FC3 점수가 golden 과 비트 일치 + 클럭 수 정상
        + 묶음마다 (11/15 검수 V03) 구간 줄이 파일 이름과 맞고, 이미지 줄이 그 구간에 정확히 묶음 크기만큼,
          TB 마지막 줄 "*** tb_npu_top PASS ***", 완료 표시 .done 의 스탬프가 지금 것과 같고 xsim 종료 코드 0
        아니면 1
"""
import argparse, glob, os, re, sys, time

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

LINE = re.compile(r"^img (\d+) : FC3 (\d+)/10 match \| pred (-?\d+) label (\d+) \| (\d+) clk \| (PASS|FAIL)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chunks", default="build/accuracy/chunks")
    ap.add_argument("--gold", default="build/golden_10k")
    ap.add_argument("--total", type=int, default=10000)
    ap.add_argument("--chunk", type=int, default=500)
    ap.add_argument("--stamp", default=None, help="stamp.txt (주면 묶음마다 .done 의 스탬프와 종료 코드를 확인)")
    ap.add_argument("--seconds", type=int, default=-1, help="이번 실행에 걸린 시간 (이어 돌린 경우 이번 실행분만)")
    ap.add_argument("--out", default="reports/accuracy_10k.txt")
    args = ap.parse_args()

    lab = [int(s) for s in open(os.path.join(args.gold, "labels.txt")).read().split()]
    py_pred = [int(s) for s in open(os.path.join(args.gold, "pred.txt")).read().split()]

    seen = {}                  # img -> (fc3 일치 줄 수, 예측, label, 클럭 수, PASS/FAIL)
    dup = 0
    logs = sorted(glob.glob(os.path.join(args.chunks, "chunk_*.log")))
    n_timeout = 0
    sim_ms = 0.0
    stamp = open(args.stamp, encoding="utf-8").read().splitlines()[0] if args.stamp else None
    chunk_bad = []             # (파일, 이유)
    starts = []
    for fn in logs:
        name = os.path.basename(fn)
        mm = re.search(r"chunk_(\d+)\.log$", fn)
        b = int(mm.group(1)) if mm else -1
        starts.append(b)
        e = b + args.chunk - 1
        n_in, has_mode, has_pass = 0, False, False
        mode_re = re.compile(r"^ mode +: ACC_ONLY .*images %d \.\. %d$" % (b, e))
        for line in open(fn, encoding="utf-8", errors="replace"):
            line = line.rstrip("\r\n")
            if mode_re.match(line):
                has_mode = True
            if "*** tb_npu_top PASS ***" in line:
                has_pass = True
            m = LINE.match(line)
            if m and b <= int(m.group(1)) <= e:
                n_in += 1
            elif m:
                chunk_bad.append((name, "image %s outside the chunk range" % m.group(1)))
        if not has_mode:
            chunk_bad.append((name, "no range line 'images %d .. %d'" % (b, e)))
        if not has_pass:
            chunk_bad.append((name, "no final '*** tb_npu_top PASS ***' line"))
        if n_in != args.chunk:
            chunk_bad.append((name, "%d image lines, expected %d" % (n_in, args.chunk)))
        if stamp is not None:
            dn = fn[:-4] + ".done"
            dl = open(dn, encoding="utf-8").read().splitlines() if os.path.isfile(dn) else []
            if not dl:
                chunk_bad.append((name, "no completion marker .done"))
            else:
                if dl[0] != stamp:
                    chunk_bad.append((name, ".done stamp differs from the current build"))
                if "rc 0" not in dl[1:]:
                    chunk_bad.append((name, ".done exit code is not 0"))
    want_starts = list(range(0, args.total, args.chunk))
    if sorted(starts) != want_starts:
        chunk_bad.append(("chunks", "%d chunk logs do not cover 0..%d in steps of %d" % (len(starts), args.total - 1, args.chunk)))
    for fn in logs:
        for line in open(fn, encoding="utf-8", errors="replace"):
            m = LINE.match(line)
            if m:
                i = int(m.group(1))
                dup += i in seen
                seen[i] = (int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)), m.group(6))
            elif "TIMEOUT" in line:
                n_timeout += 1
            elif "Simulation CPU Usage" in line:
                mm = re.search(r"Simulation CPU Usage: (\d+) ms", line)
                if mm: sim_ms += int(mm.group(1))

    n = args.total
    missing = [i for i in range(n) if i not in seen]
    extra = [i for i in seen if i >= n]
    have = [i for i in range(n) if i in seen]
    bit_ok = [i for i in have if seen[i][0] == 10]
    clk = sorted(set(seen[i][3] for i in have))
    clk_ok = [i for i in have if seen[i][3] == 119009]
    correct = [i for i in have if seen[i][1] == lab[i]]
    lab_bad = [i for i in have if seen[i][2] != lab[i]]            # TB 가 읽은 label 이 golden labels.txt 와 같은지
    vs_py = [i for i in have if seen[i][1] != py_pred[i]]          # RTL 예측 != 파이썬 정수 모델 예측
    wrong = [i for i in have if seen[i][1] != lab[i]]
    passed = [i for i in have if seen[i][4] == "PASS"]

    ok = (not missing and not extra and dup == 0 and n_timeout == 0 and len(bit_ok) == n and len(clk_ok) == n
          and not lab_bad and not vs_py and len(passed) == n and not chunk_bad)

    rep = []
    rep.append("accuracy_%s : RTL simulation of npu_top (tb_npu_top, ACC_ONLY mode), xsim, real blk_mem_gen IP models, RD_LAT = 1" % (
        "10k" if n == 10000 else n))
    rep.append("written           : %s   (scripts/run_accuracy.sh -> scripts/accuracy_report.py)" % time.strftime("%Y-%m-%d %H:%M:%S"))
    rep.append("images            : %d of %d (MNIST test set, in order), %d chunk logs, missing %d, duplicated %d" % (
        len(have), n, len(logs), len(missing), dup))
    rep.append("FC3 scores        : %d / %d images bit-identical to the python integer golden (10 of 10 scores)" % (len(bit_ok), n))
    rep.append("clock count       : %d / %d images at 119009 clocks (values seen: %s)" % (len(clk_ok), n, ", ".join(str(c) for c in clk)))
    rep.append("RTL accuracy      : %d / %d = %.2f %%   (argmax of the 10 scores read from OMEM vs label)" % (
        len(correct), len(have), 100.0 * len(correct) / max(len(have), 1)))
    rep.append("python int model  : %d / %d = %.2f %%   (reports/accuracy_golden_10k.txt)" % (
        sum(1 for i in range(n) if py_pred[i] == lab[i]), n, 100.0 * sum(1 for i in range(n) if py_pred[i] == lab[i]) / n))
    rep.append("RTL vs python     : %d images with a different prediction" % len(vs_py))
    rep.append("timeouts          : %d" % n_timeout)
    if chunk_bad:
        rep.append("chunk checks      : %d problems (see below)" % len(chunk_bad))
    else:
        rep.append("chunk checks      : %d chunks of %d all complete (range line, image count, final PASS line%s)" % (
            len(logs), args.chunk, ", .done stamp + exit code 0" if stamp else "; .done not checked"))
    if sim_ms > 0:
        rep.append("simulator CPU time: %.0f s in total (sum over chunks), %.2f s per image" % (sim_ms / 1000.0, sim_ms / 1000.0 / max(len(have), 1)))
    if args.seconds >= 0:
        rep.append("wall time         : %d s for the last invocation of run_accuracy.sh (finished chunks are skipped on a re-run)" % args.seconds)
    rep.append("not checked here  : FC1 / FC2 outputs (ACC_ONLY skips them; the 100-image regression checks them), per-clock checker")
    rep.append("RESULT            : %s" % ("PASS" if ok else "FAIL"))
    rep.append("")
    for f, why in chunk_bad[:20]:
        rep.append("chunk problem: %s : %s" % (f, why))
    if missing:
        rep.append("missing images (first 20): %s" % ", ".join(str(i) for i in missing[:20]))
    bad_bits = [i for i in have if seen[i][0] != 10]
    if bad_bits:
        rep.append("images with FC3 mismatch (first 20): %s" % ", ".join(str(i) for i in bad_bits[:20]))
    rep.append("misclassified by the RTL (%d images): image index, predicted -> label" % len(wrong))
    for i in wrong:
        rep.append("  img %5d : pred %d  label %d" % (i, seen[i][1], lab[i]))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rep) + "\n")
    print("\n".join(rep[:15]))
    print("-> %s" % args.out)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
