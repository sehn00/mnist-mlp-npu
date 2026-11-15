"""
check_ip.py : 시뮬레이션·합성 전에 BRAM IP 10개 설정과 RTL 의 RD_LAT 가 맞는지 검사 (11/15 외부 검수 D03)

  python scripts/check_ip.py                 # RTL 기본값(rtl/npu_top.v 의 parameter RD_LAT)으로 검사
  python scripts/check_ip.py --rd-lat 2      # 예전 ON 구성(run_sim.tcl oreg_on)으로 검사

보는 것 (IP 10개 각각)
  .xci (vivado_sim/aissd_D_sim.srcs/sources_1/ip/<ip>/<ip>.xci)
    - Native, Single_Port_RAM, 바이트 쓰기 OFF
    - 폭(Write/Read_Width_A)과 깊이(Write_Depth_A)가 아래 표와 같음
    - Primitives Output Register: RD_LAT = 1 이면 전부 OFF (과제 가이드 p.9),
      RD_LAT = 2 이면 WMEM 4개와 BMEM 만 ON (예전 조원2 11/12 구성), 나머지는 OFF
    - Core Output Register: 항상 OFF (켜면 지연이 하나 더 늘어남. RTL 은 1 또는 2만 지원)
    - 초기화 파일: WMEM/BMEM 은 coe/ 의 정해진 파일을 가리켜야 하고, 나머지는 초기화 없음
  생성된 시뮬레이션 모델 (vivado_sim/aissd_D_sim.gen/sources_1/ip/<ip>/sim/<ip>.v) - xsim 이 실제로 쓰는 것
    - C_READ_WIDTH_A / C_READ_DEPTH_A / C_HAS_MEM_OUTPUT_REGS_A / C_HAS_MUX_OUTPUT_REGS_A 가 위와 같음
  생성된 초기화 파일 (.mif) 이 coe/ 의 COE 와 워드 단위로 같음 (COE 를 바꾸고 IP 를 다시 안 만들면 여기서 걸림)
  RTL: rtl/npu_top.v, npu_ctrl.v, npu_mem_ctrl.v 의 parameter RD_LAT 기본값이 셋 다 같음
반환값: 0 = 전부 맞음, 1 = 하나라도 다름, 2 = 파일이 없음
"""
import argparse, json, os, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRCS = os.path.join(ROOT, "vivado_sim", "aissd_D_sim.srcs", "sources_1", "ip")
GEN = os.path.join(ROOT, "vivado_sim", "aissd_D_sim.gen", "sources_1", "ip")

# 이름: (폭, 깊이, COE 파일 또는 None, RD_LAT=2 에서 출력 레지스터를 켜는지)
IPS = {
    "wmem_bank0":  (32, 29280, "weight_bank0.coe", True),
    "wmem_bank1":  (32, 29280, "weight_bank1.coe", True),
    "wmem_bank2":  (32, 29280, "weight_bank2.coe", True),
    "wmem_bank3":  (32, 29280, "weight_bank3.coe", True),
    "bmem_128":    (128, 163,  "bias_128bit.coe",  True),
    "imem_a_bram": (32, 196,   None, False),
    "imem_b_bram": (32, 196,   None, False),
    "act_a_bram":  (32, 128,   None, False),
    "act_b_bram":  (32, 32,    None, False),
    "omem_bram":   (32, 10,    None, False),
}


def rtl_rd_lat():
    vals = {}
    for f in ("npu_top.v", "npu_ctrl.v", "npu_mem_ctrl.v"):
        txt = open(os.path.join(ROOT, "rtl", f), encoding="utf-8", errors="replace").read()
        m = re.search(r"parameter\s+RD_LAT\s*=\s*(\d+)", txt)
        vals[f] = int(m.group(1)) if m else None
    return vals


def xci_params(path):
    d = json.load(open(path, encoding="utf-8"))
    cp = d["ip_inst"]["parameters"]["component_parameters"]
    return {k: v[0].get("value") for k, v in cp.items() if isinstance(v, list) and v}


def sim_params(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    return {k: v for k, v in re.findall(r"\.(C_[A-Z0-9_]+)\(([^)]*)\)", txt)}


def coe_words(path, width):
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;", txt, re.I)
    radix = int(m.group(1)) if m else 16
    vec = re.split(r"memory_initialization_vector\s*=", txt, flags=re.I)[1]
    toks = [t for t in re.split(r"[\s,;]+", vec) if t]
    return [int(t, radix) & ((1 << width) - 1) for t in toks]


def mif_words(path):
    return [int(l.strip(), 2) for l in open(path, encoding="utf-8") if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rd-lat", type=int, default=None, help="검사할 읽기 지연 (기본: rtl/npu_top.v 의 기본값)")
    args = ap.parse_args()

    errs, notes = [], []
    rl = rtl_rd_lat()
    if len(set(rl.values())) != 1 or None in rl.values():
        errs.append("RTL parameter RD_LAT defaults differ or missing: %s" % rl)
    rd_lat = args.rd_lat if args.rd_lat is not None else rl["npu_top.v"]
    if rd_lat not in (1, 2):
        errs.append("RD_LAT = %s is not supported (1 or 2 only)" % rd_lat)
    if args.rd_lat is not None and args.rd_lat != rl["npu_top.v"]:
        notes.append("RD_LAT %d given on the command line (RTL default is %s; the testbench must pass RD_LAT=%d)"
                     % (args.rd_lat, rl["npu_top.v"], args.rd_lat))

    rows = []
    for ip, (w, dep, coe, on_in_2) in IPS.items():
        xci = os.path.join(SRCS, ip, ip + ".xci")
        simv = os.path.join(GEN, ip, "sim", ip + ".v")
        if not os.path.isfile(xci) or not os.path.isfile(simv):
            print("[check_ip] missing %s or %s (run run_sim.tcl first)" % (xci, simv))
            return 2
        p = xci_params(xci)
        s = sim_params(simv)
        want_prim = (rd_lat == 2 and on_in_2)
        bad = []

        def need(cond, msg):
            if not cond:
                bad.append(msg)
        need(p.get("Interface_Type") == "Native", "Interface_Type %s" % p.get("Interface_Type"))
        need(p.get("Memory_Type") == "Single_Port_RAM", "Memory_Type %s" % p.get("Memory_Type"))
        need(p.get("Use_Byte_Write_Enable") == "false", "byte write enable on")
        need(p.get("Write_Width_A") == str(w) and p.get("Read_Width_A") == str(w),
             "width %s/%s (want %d)" % (p.get("Write_Width_A"), p.get("Read_Width_A"), w))
        need(p.get("Write_Depth_A") == str(dep), "depth %s (want %d)" % (p.get("Write_Depth_A"), dep))
        prim = p.get("Register_PortA_Output_of_Memory_Primitives") == "true"
        core = p.get("Register_PortA_Output_of_Memory_Core") == "true"
        need(prim == want_prim, "primitives output register %s (want %s for RD_LAT %d)"
             % ("ON" if prim else "OFF", "ON" if want_prim else "OFF", rd_lat))
        need(not core, "core output register ON (must be OFF)")
        # 생성된 시뮬레이션 모델
        need(s.get("C_READ_WIDTH_A") == str(w), "sim model C_READ_WIDTH_A %s" % s.get("C_READ_WIDTH_A"))
        need(s.get("C_READ_DEPTH_A") == str(dep), "sim model C_READ_DEPTH_A %s" % s.get("C_READ_DEPTH_A"))
        need(s.get("C_HAS_MEM_OUTPUT_REGS_A") == ("1" if want_prim else "0"),
             "sim model C_HAS_MEM_OUTPUT_REGS_A %s (project not regenerated? use run_sim.tcl ... fresh)" % s.get("C_HAS_MEM_OUTPUT_REGS_A"))
        need(s.get("C_HAS_MUX_OUTPUT_REGS_A") == "0", "sim model C_HAS_MUX_OUTPUT_REGS_A %s" % s.get("C_HAS_MUX_OUTPUT_REGS_A"))
        # 초기화
        init = "-"
        if coe:
            need(p.get("Load_Init_File") == "true", "Load_Init_File off")
            cf = p.get("Coe_File") or ""
            cpath = os.path.normpath(os.path.join(os.path.dirname(xci), cf))
            want = os.path.normpath(os.path.join(ROOT, "coe", coe))
            need(os.path.normcase(cpath) == os.path.normcase(want), "Coe_File %s (want coe/%s)" % (cf, coe))
            mif = os.path.join(GEN, ip, ip + ".mif")
            if not os.path.isfile(mif):
                bad.append("generated %s.mif missing" % ip)
            else:
                cw, mw = coe_words(want, w), mif_words(mif)
                cw = cw + [0] * (dep - len(cw))
                if len(mw) != dep or cw != mw:
                    nd = sum(1 for a, b in zip(cw, mw) if a != b) + abs(len(cw) - len(mw))
                    bad.append("generated .mif differs from coe/%s (%d words; regenerate the IP)" % (coe, nd))
                else:
                    init = "coe/%s = .mif (%d words)" % (coe, dep)
        else:
            need(p.get("Load_Init_File") == "false", "Load_Init_File on (expected no init)")
        lat = 1 + prim + core
        rows.append((ip, "%dx%d" % (w, dep), lat, init, bad))
        errs += ["%s: %s" % (ip, b) for b in bad]

    print("check_ip : RTL RD_LAT defaults %s, checking for RD_LAT %s" % (
        ", ".join("%s %s" % (k, v) for k, v in rl.items()), rd_lat))
    for ip, wd, lat, init, bad in rows:
        print("  %-12s %-8s read latency %d  %-36s %s" % (ip, wd, lat, init, "OK" if not bad else "BAD: " + "; ".join(bad)))
    for n in notes:
        print("  note: " + n)
    for e in errs:
        if ":" not in e or e.split(":")[0] not in IPS:
            print("  BAD: " + e)
    print("check_ip : %s (%d problems)" % ("PASS" if not errs else "FAIL", len(errs)))
    return 0 if not errs else 1


if __name__ == "__main__":
    sys.exit(main())
