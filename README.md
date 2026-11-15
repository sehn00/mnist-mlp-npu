# D 블록 (npu_ctrl + npu_top) + A·B·C·D 통합 · 2026-11-14 (11/15 회귀·정확도 추가) · 조원4

## 결과 요약 (Vivado 2024.2, 실제 Block Memory Generator IP, xck26-sfvc784-2LV-c)
**구성: 모든 BRAM의 Primitives Output Register OFF (과제 가이드 p.9), 읽기 지연 1클럭, RD_LAT=1**

| 단계 | 결과 | 핵심 숫자 | 근거 파일 |
|---|---|---|---|
| D 단위 `tb_npu_ctrl` (RD_LAT=1) | **PASS** | GO 512/128/10 · bias_we 650 · 마지막 o_waddr 117,055 · **119,009클럭** · 경고 0개 | `reports/sim_100img.txt` |
| 통합 `tb_npu_top` 100장 | **PASS** | **100/100장 FC1/FC2/FC3 golden v2 비트 일치, 예측 100/100**, 장당 **119,009클럭**(약 1.19 ms), 시뮬레이터 경고 0개 | 〃 |
| 전체 회귀 `run_regress.sh` (11/15 오후, D01·D07·V01 반영 후) | **PASS (11단계 전부)** | IP 설정 검사 PASS · golden 100장 100/100 + 매 클럭 검사기 2억 8,462만 번 검사에 에러 0 · 합성 이미지 16장 16/16 (포화 FC1 24번, FC2 1번 포함) · 예외 상황 판정 16개 PASS (done 직후 start·읽기 포함) · 363초 | `reports/regress_summary.txt` |
| 테스트셋 정확도, 파이썬 정수 모델 (MNIST 1만 장) | 완료 | **9,930 / 10,000 = 99.30%** (float 99.32%). 앞 100장은 기존 golden hex와 비트 일치 | `reports/accuracy_golden_10k.txt` |
| 테스트셋 정확도, RTL 시뮬 (MNIST 1만 장) | **PASS** (11/15 완료) | **9,930 / 10,000 = 99.30%**. 1만 장 전부 FC3 점수 10개가 golden과 비트 일치, 전부 장당 119,009클럭, 파이썬 모델과 예측이 다른 이미지 0장, 타임아웃 0. **1만 장은 커밋 74c88dd 기준** (RTL·TB 스탬프로 확인). 그 뒤 D01은 완료 신호(o_done) 타이밍만 바꿔서 계산 결과에는 영향 없음, 회귀로 확인 (golden 100장 + 합성 이미지 16장 비트 일치, 장당 119,009클럭 그대로). 1만 장은 다시 안 돌림 | `reports/accuracy_10k.txt` |
| 합성 (`npu_top`, 10 ns 클럭, 11/15 D01 후 다시) | 완료 | LUT 1,400 · FF 283 · RAMB36 106 + RAMB18 13 · DSP 0 | `reports/synth_*.rpt` |
| 구현 (place & route, 11/15 D01 후 다시) | **100 MHz 타이밍 충족** | **WNS +2.709 ns · WHS +0.031 ns** (실패 경로 0 / 2,165). `run_impl.tcl` 반환값 0 (둘 다 > 0일 때만 0) | `reports/impl_timing_*.rpt`, `reports/impl_summary.txt` |
| 전력 (구현 후, vectorless 추정) | 완료 | **합계 0.366 W** = 동적 0.077 W + 정적 0.289 W | `reports/impl_power*.rpt` |

구현 후 자원 사용량 (K26 전체 대비)

| 자원 | 사용 | 전체 | 비율 | 블록별 |
|---|---|---|---|---|
| CLB LUT | 1,183 | 117,120 | 1.0% | B 762 (memory_controller + BRAM IP 내부 730, 어댑터 32) · D 197 · C 155 · A 71 |
| FF | 283 | 234,240 | 0.12% | A 97 · C 97 · D 60 · B 29 |
| BRAM 타일 | **112** | 144 | **77.8%** | RAMB36 106 + RAMB18 12. WMEM 뱅크당 RAMB36 26 + RAMB18 2, BMEM RAMB36 2, IMEM_A·ACT_A·ACT_B·OMEM 각 RAMB18 1 |
| DSP | 0 | 1,248 | 0% | C의 8×8 곱셈 4개가 LUT로 구현됨 |
| 핀 (IOB) | 82 | 189 | 43% | 핀 배치 제약 없음 (자동 배치) |

전력 breakdown (동적 0.077 W): BRAM 0.038 W · I/O 0.025 W · Signals 0.006 W · Logic 0.004 W · Clocks 0.004 W. 정적 0.289 W. 스위칭 정보 파일 없이 Vivado 기본값으로 추정한 값이라 Confidence Level은 Low (가이드 p.39 예시도 Low).

출력 레지스터 ON(이전, `reports/archive_oreg_on/`) vs OFF(지금) 비교

| 항목 | ON (RD_LAT=2, 가이드 위반) | **OFF (RD_LAT=1, 지금)** |
|---|---|---|
| 장당 클럭 수 | 119,659 | **119,009** (뉴런당 1클럭 × 650 감소) |
| golden v2 일치 | 100/100 | 100/100 |
| CLB LUT / FF | 1,199 / 341 | 1,183 / 283 |
| BRAM 타일 / DSP | 112 / 0 | 112 / 0 |
| WNS / WHS | +2.138 / +0.041 ns | **+2.709 / +0.031 ns** (D01 전 +2.553 / +0.054) |
| 가장 느린 경로 | D 주소 포인터 → WMEM enable (7.22 ns) | WMEM 출력 → C 곱셈 → 곱 레지스터 (7.02 ns) |
| 전력 | 측정 안 함 (그때는 전력 리포트가 스크립트에 없었음) | 0.366 W |

- 가장 느린 경로: WMEM 뱅크0 BRAM 출력 → 뱅크 안 BRAM 26개 중 고르는 MUX → 4뱅크 MUX → C의 8×8 곱셈(LUT) → 곱 레지스터 `u_C/p0_reg[15]`. 지연 7.02 ns (로직 45%, 배선 55%, 로직 11단, 11/15 D01 후 구현 기준). 출력 레지스터를 꺼서 BRAM 출력부터 곱셈까지가 한 클럭 안에 들어왔지만 여유가 2.71 ns 남아. 가장 빠듯한 hold 경로는 A 안(`r_pack` → `o_wdata`, +0.031 ns). D01은 o_done 레지스터의 set 조건만 바꾼 거라 경로 차이는 배치·배선 결과가 달라진 몫
- 아직 안 한 것: 핀 배치(PACKAGE_PIN), I/O 지연 제약, 구현 후(post-route) 시뮬레이션, 보드 동작. 타이밍 리포트는 칩 내부 레지스터 사이 경로만 검사한 결과야 (입력 47개, 출력 34개 포트는 I/O 지연 제약 없음).
- iverilog + BRAM 행동 모델(`sim_models/`)로는 조원4가 같은 RTL 조합에서 RD_LAT=1 100장 PASS(119,009클럭), RD_LAT=2(`-DOREG_ON`) 10장 PASS를 확인했고, Vivado 결과와 같아.
- 합성·구현 **로그**에 critical warning 0개. 경고는 OOC 클럭 주기 차이(Timing 38-316), 어댑터의 안 쓰는 주소 비트(Synth 8-7129), RD_LAT=1에서 안 쓰여 지워진 RD_LAT=2용 레지스터 3개(Synth 8-6014)뿐. 단, 구현 후 **DRC 리포트**에는 Critical Warning 2건이 있어: NSTD-1(I/O 표준 미지정), UCIO-1(핀 위치 미지정), 포트 82개 전부 해당 (`reports/review/drc_routed.rpt`). 핀 제약이 없어서 생기는 것이고, 이 상태로는 비트스트림을 못 만들어 (4절 #13).

## 1. 폴더 구성
```
rtl/
  npu_ctrl.v        D 제어기 (조원4)
  npu_top.v         최상위 (조원4)
  npu_mem_ctrl.v    B 임시 어댑터 (조원4, memory_controller.v를 수정 없이 감쌈)
  npu_postproc.v    A (조원1 blockA_share 그대로)
  npu_pe_array.v    C (handoff_D_1112/rtl 버전 그대로: i_clk/i_rstn 이름)
  memory_controller.v  B (조원2 memory_controller.zip 그대로)
tb/
  tb_npu_ctrl.v     D 단위 TB (클럭 수 검사, 타임아웃 포함)
  tb_npu_top.v      통합 TB (이미지 N장, 클럭 수 검사. `ACC_ONLY` define = 정확도 전용 모드, `+IMG_BASE=n` = n번 이미지부터)
  review/
    npu_checker.v   매 클럭 검사기 (TB 옆에 두 번째 top으로 같이 올림. 조건 A1~A15)
    tb_edge.v       예외 상황 TB 12종 (연산 중 start·리셋·외부 접근, done 직후 읽기 등)
run_regress.sh      전체 회귀를 명령 하나로 (Git Bash, 3절 0번)
scripts/
  gen_golden_10k.py   MNIST 테스트셋 1만 장 입력 hex + 정답 생성 (앞 100장이 hex/와 비트 일치하는지 먼저 확인)
  run_accuracy.sh     테스트셋 정확도 RTL 시뮬 (1만 장, 500장씩 나눠 돌리고 끊기면 이어서 함)
  run_accuracy_detached.ps1  위 스크립트를 창·세션과 분리된 프로세스로 띄움 (이어 돌리기 겸용)
  accuracy_report.py  위 결과를 모아 reports/accuracy_10k.txt 작성
  review/             리뷰용: xrun.sh(XSim 단독 실행기), golden_check.py, gen_stress.py, 버그 주입 등
constr/
  npu_top.xdc       10 ns 클럭 제약, 가이드 p.33과 같은 한 줄 (핀 배치 없음)
coe/                BRAM 초기값 (조원2 zip의 weight_bank0~3.coe, bias_128bit.coe 그대로)
hex/                통합 TB용 golden v2 (handoff_D_1112/golden과 같은 파일) + iverilog용 뱅크 초기값
run_sim.tcl / run_sim.bat   Vivado batch 시뮬레이션 (프로젝트 vivado_sim/ 생성, IP 10개 생성, 두 TB 실행)
run_impl.tcl                Vivado batch 합성 + 구현 + 리포트
reports/            시뮬 결과(sim_100img.txt), 회귀 요약(regress_summary.txt), 테스트셋 정확도(accuracy_10k.txt, accuracy_golden_10k.txt), 합성·구현 사용량/타이밍/전력 리포트, impl_summary.txt
  archive_oreg_on/  출력 레지스터 ON 구성(폐기) 결과, 비교용
  review/           독립 검증 리뷰(docs/review_1114.md)의 근거 리포트
patches/            RD_LAT=1 전환 패치 원본 (반영 완료)
sim_models/
  bram_models.v     iverilog 전용 BRAM 모델. Vivado에는 넣지 말 것! initial/readmemh가 있어서 제출 zip에서도 뺄 것
wave_fc2_n27_n28.png  통합 파형 (FC2 뉴런 27 → 28 경계, iverilog)
```

## 2. 설계 핵심
- FSM 상태 6개 (스펙 6-2): IDLE → ISSUE(L클럭) → WAIT(RD_LAT+1클럭) → GO → … → LAYER / DONE
- 레이어 설정표: golden v2 기준 shift FC1 **11**, FC2 **7** (스펙 v0.2 표는 아직 10/9)
- 메모리 흐름 (handoff 11/12 기준): FC1 IMEM_A → ACT_A, FC2 ACT_A → ACT_B, FC3 ACT_B → OMEM
- `RD_LAT` parameter (npu_top, npu_mem_ctrl, npu_ctrl 공통, 기본 1): 과제 가이드 p.9 규칙대로 BRAM 출력 레지스터 OFF = 읽기 지연 1. 조원2 11/12 IP(WMEM/BMEM 출력 레지스터 ON)를 그대로 쓸 때만 2 (TB에서 `OREG_ON` define). 1과 2 말고 다른 값을 주면 시뮬레이션(elaboration)과 합성 둘 다 에러로 멈춤 (11/15 검수 D07, `ERROR_npu_ctrl_RD_LAT_must_be_1_or_2` 모듈을 못 찾는다는 에러)
- WMEM 주소를 두 가지로 냄: `o_waddr`(스펙의 단일 WMEM 기준), `o_wbank_addr`+`o_wbank_sel`(B의 4뱅크 구조 기준).
  곱셈·나눗셈 없이 포인터 +1, 뉴런의 마지막 줄에서 lane ≠ 3이면 묶음 시작으로 되돌림
- **npu_top을 바깥(TB)에서 쓰는 순서**: IMEM_A에 이미지 쓰기 → `i_start` 1클럭 → **`o_done == 1`을 기다리기** → 결과 읽기 (스펙 v0.2 6-1 순서 그대로).
  - (11/15 외부 검수 D01 반영) `o_done`은 마지막 OMEM 쓰기(A가 OMEM 9번에 점수를 쓰는 DONE 상태 클럭)가 끝나는 엣지에 1이 되고, 같은 엣지에 상태가 IDLE로 가서 `o_busy`가 0이 돼. 그래서 **`o_done = 1`이면 항상 `o_busy = 0`**이고 결과가 다 써져 있어. 바로 읽어도 되고, 그 클럭의 `i_start`도 받아들여져 (`tb_edge` S07, S12가 판정). 예전 조건 `o_busy == 0 && o_done == 1`도 그대로 맞아.
  - 예전(11/15 이전)에는 `o_done`이 `o_busy`보다 1클럭 먼저 올라가서 `o_done`만 보고 읽으면 첫 읽기가 무시됐어 (리뷰 R05). 연산 길이는 그대로: start를 받은 엣지 → `o_done`이 올라가는 엣지 = `o_busy`가 1인 클럭 수 = **119,009클럭** (RD_LAT=1).
  - 스펙 v0.2 6-2절 타이밍 표에서 "DONE 상태 클럭에 o_done = 1"은 "DONE 다음(IDLE로 가는) 엣지에 o_done = 1, 같은 엣지에 busy = 0"으로 고쳐야 함 (스펙 갱신 목록 #5에 추가).
  - `i_start`는 1클럭 펄스로 줄 것. 끝난 뒤까지 계속 1로 두면 다시 시작해 (R06).
  - 외부 포트 주소는 줄 수 안에서만 쓸 것 (IMEM_A 0~195, ACT_A 0~127, ACT_B 0~31, OMEM 0~9). 범위 검사가 없고 윗주소 비트는 무시돼 (R09). `o_dout`은 주소를 준 다음 클럭 1클럭 동안만 유효.
- (11/14 수정) 되돌리는 시점을 GO에서 ISSUE 마지막 클럭으로 옮김. B의 WMEM은 ena가 1로 고정이라 ISSUE가 아닌 클럭의 주소도 실제로 읽히는데, 예전 방식은 FC3 마지막 묶음에서 포인터가 29,280(범위 밖)에 4클럭 머물러서 IP 모델이 `Address 7260 is outside range` 경고를 사진당 32번 냈어. 그 데이터는 안 쓰여서 결과는 같았고, 지금은 주소가 항상 0~29,279 안에 있어 (TB가 매 클럭 검사).

## 3. 다시 돌리는 방법 (Vivado 2024.2)
0. **전체 회귀 (명령 하나, Git Bash)**: 아래 1번을 한 번 돌려서 `vivado_sim/`(BRAM IP 모델)이 있는 상태에서
   ```
   bash run_regress.sh        (통합 TB golden 100장, 전체 약 5분)
   bash run_regress.sh 10     (10장, 빠른 확인용)
   ```
   Vivado 프로젝트를 열지 않고 xvlog → xelab → xsim만 써. 하나라도 FAIL이면 반환값 1. 요약은 `logs/regress_summary.txt`, 단계별 로그는 `logs/regress/`. 돌리는 11단계:

   | 단계 | 내용 |
   |---|---|
   | rules | `rtl/`에 `initial`, `#지연`, `$readmemh/b`가 없는지 (가이드 p.4-5) |
   | ip_check | (11/15 검수 D03) `scripts/check_ip.py`: BRAM IP 10개의 폭·깊이·Primitives/Core 출력 레지스터(.xci와 생성된 시뮬 모델 둘 다)와 생성된 `.mif` == `coe/`를 RTL의 `RD_LAT` 기본값과 대조 |
   | golden_check | `.pt`에서 다시 계산한 가중치·bias·사진 100장 결과 == 팀 golden hex (33항목) |
   | gen_stress | 합성 이미지 16장 + 정답 생성 (포화, 레인별, 난수). golden 100장에는 포화가 한 번도 없어서 필요 |
   | ctrl_rd1, ctrl_rd2 | `tb_npu_ctrl` (D 단위), RD_LAT = 1 / 2. 클럭 수 119,009 / 119,659 검사 + 타임아웃 |
   | top100_chk | `tb_npu_top` golden 100장 + `npu_checker`(매 클럭 검사기, 조건 15종) |
   | stress16_chk | `tb_npu_top` 합성 이미지 16장 + 검사기 |
   | edge_chk | `tb_edge` 예외 상황 12종(연산 중 start·리셋·외부 접근, done 직후 start·읽기 등) + 검사기 |
   | model_rd1, model_rd2 | BRAM 행동 모델(`sim_models/`)로 2장. rd2는 예전 OREG_ON 구성 |

1. **시뮬레이션 (Vivado 프로젝트 + IP 생성)**: `run_sim.bat` 더블클릭 (`run_sim.bat 100`처럼 인자를 줄 수 있음). 또는
   ```
   mkdir logs
   vivado -mode batch -source run_sim.tcl -log logs/run_sim.log -journal logs/run_sim.jou -notrace                (10장)
   vivado -mode batch -source run_sim.tcl -log logs/run_sim.log -journal logs/run_sim.jou -notrace -tclargs 100   (100장)
   ```
   새 프로젝트 `vivado_sim/`를 만들고(이미 있으면 재사용), 조원2 .xci와 같은 설정에서 **Primitives Output Register만 전부 OFF로 바꿔서** BRAM IP 10개를 2024.2에서 새로 만든 다음 `tb_npu_ctrl` → `tb_npu_top`을 돌려. 결과는 `result.txt`, 로그는 `logs/`. **두 TB가 다 PASS여야 반환값 0, 아니면 1** (`result.txt` 마지막 줄 `RESULT: PASS / FAIL`). 기존 `aissd_mnist_npu` 프로젝트는 건드리지 않아. 10장은 1~2분, 100장도 몇 분이면 끝나. IP 설정을 바꿨으면 `-tclargs 100 fresh`로 프로젝트를 새로 만들어야 해 (설정이 안 맞으면 스크립트가 멈추고 알려 줘). 예전 ON 구성은 `-tclargs 10 fresh oreg_on`. 인자 순서는 상관없어 (`fresh`만 써도 됨).
   시뮬 전에 `scripts/check_ip.py`로 IP 10개 설정(폭·깊이·출력 레지스터·초기화 파일)이 RTL의 RD_LAT와 맞는지 검사하고, 안 맞으면 반환값 1로 멈춰 (11/15 검수 D03). 파이썬은 PATH의 `python`을 쓰고, 다른 걸 쓰려면 `NPU_PYTHON` 환경 변수에 python.exe 경로 (`PYTHON`은 Vivado가 자기 폴더로 덮어써서 못 씀).
2. **합성 + 구현**: 시뮬을 한 번 돌린 뒤
   ```
   vivado -mode batch -source run_impl.tcl -log logs/run_impl.log -journal logs/run_impl.jou -notrace
   ```
   결과는 `result_impl.txt`, 리포트는 `reports/` (사용량, 타이밍, 전력). IP가 이미 합성돼 있으면 약 10분, 처음이면 IP 10개 합성 때문에 더 걸려.
   **반환값 (11/15 검수 V02, D03)**: 0 = 성공. 1 = 합성 전 IP 검사(`check_ip.py`) 실패, 합성·구현 실패, 또는 구현 후 setup/hold 검사 경로가 없거나 **WNS ≤ 0 또는 WHS ≤ 0** (가이드 p.5 "slack 양수"). 타이밍이 실패해도 리포트와 `result_impl.txt`는 다 쓰고 끝나. 마지막 줄 `RESULT: PASS / FAIL`.
   **주의**: 병렬 작업 수(`JOBS`)는 2로 둘 것. 8로 돌렸더니 RAM 16GB PC에서 메모리가 바닥나 IP 합성 런 3개가 에러 메시지 없이 죽었어.
3. **GUI로 직접 넣을 때**: Design Sources에 `rtl/` 6개, IP는 조원2 zip의 `ip/*.xci` 10개(**WMEM 4개와 BMEM은 Port A Options에서 Primitives Output Register 체크를 끌 것**, 각 IP의 COE 경로를 내 PC 경로로 지정 후 Generate Output Products. 2024.1에서 만든 IP라 2024.2에서 잠겨 보이면 Upgrade IP), Simulation Sources에 `tb/` 2개. `sim_models/bram_models.v`는 **넣지 않음**(IP와 이름이 겹침). `tb_npu_top.v` 맨 위 `HEX_DIR`을 내 PC의 `hex/` 절대경로로 변경(슬래시 `/`, 끝에 `/`). 합성할 때는 `constr/npu_top.xdc` 추가, top = `npu_top`.
4. 파형 캡처할 신호 추천: `u_D/r_state, r_n, r_k, valid, acc, bias_we, bias, go, lane, we, wdata, oaddr`
5. **테스트셋 정확도 (MNIST 1만 장, Git Bash)**:
   ```
   python scripts/gen_golden_10k.py     (입력 hex + 정답 1만 장 → build/golden_10k/, 몇 초. 파이썬 정수 모델 정확도도 같이 나옴)
   bash scripts/run_accuracy.sh         (RTL 시뮬 1만 장, 약 2시간 반: 500장에 약 8분. 결과 reports/accuracy_10k.txt)
   powershell -File scripts\run_accuracy_detached.ps1     (같은 일을 창·세션과 분리된 프로세스로. 창이나 Claude 세션을 닫아도 계속 돎)
   ```
   - **끝났는지 확인**: `logs/accuracy_console.txt` 마지막 줄이 `rc 0`이면 끝 (`rc 1`은 불일치 있음). 중간 진행은 `build/accuracy/progress.txt` (묶음당 한 줄).
   - **끝난 뒤 결과 확인 + 반영 (한 줄, Git Bash)**:
     ```
     python scripts/accuracy_report.py && git add reports/accuracy_10k.txt && git commit -m "Accuracy: 10,000-image RTL result"
     ```
     묶음 로그를 모아 요약(비트 일치 장수, RTL 정확도, 틀린 이미지 목록)을 화면에 찍고 `reports/accuracy_10k.txt`를 쓴 다음 커밋해. 1만 장이 다 안 끝났거나 불일치가 있으면 `RESULT: FAIL`로 끝나고 커밋은 안 돼. (`run_accuracy.sh`는 끝에 이걸 `--stamp build/accuracy/stamp.txt`와 같이 자동으로 부름)
   - 중간에 끊겼으면(PC 종료 등) 위의 `run_accuracy_detached.ps1`을 다시 실행하면 끝난 묶음은 건너뛰고 이어서 해. 도는 중에 또 실행하면 "이미 돌고 있음"이라고 하고 안 띄워. PC가 절전에 들어가면 그동안 멈췄다가 깨어나면 이어서 돌아.
   - `gen_golden_10k.py`는 MNIST 테스트셋(`~/.keras/datasets/mnist.npz`, 다른 위치면 `--mnist`)을 픽셀 >> 1로 바꾸고, **앞 100장이 `hex/`의 기존 100장(입력·label·FC1·FC2·FC3)과 비트 단위로 같은지 먼저 확인**한 뒤에만 파일을 써.
   - `run_accuracy.sh`는 `tb_npu_top`을 정확도 전용 모드(`ACC_ONLY`: FC3 점수 10개를 golden과 비교 + argmax를 label과 비교, FC1/FC2 출력은 안 읽음)로 한 번 컴파일하고 500장씩 20묶음으로 돌려. 시뮬레이션은 한 번에 하나만. 끝난 묶음은 건너뛰니까 중간에 끊겨도 같은 명령으로 이어서 할 수 있어. 진행 상황은 `build/accuracy/progress.txt`.
   - (11/15 검수 V03) 이어 돌리기 기준: 스탬프(`build/accuracy/stamp.txt`)에 RTL·TB·`xrun.sh`·컴파일 define·**생성된 BRAM IP 시뮬 모델과 `.mif`**·`coe/`·golden이 다 들어가서, 하나라도 바뀌면 처음부터 다시 해. 묶음마다 완료 표시 `chunk_<번호>.done`(스탬프 + xsim 종료 코드)을 남기고, 스탬프가 같고 종료 코드 0이고 로그에 그 묶음 구간 줄과 TB 마지막 줄이 있을 때만 "끝난 묶음"으로 건너뛰어. 집계(`accuracy_report.py`)도 묶음마다 구간 줄·이미지 수·`*** tb_npu_top PASS ***`·`.done`을 확인해. 시작 전에 `check_ip.py`도 돌려.
   - 일부만 볼 때: `bash scripts/run_accuracy.sh 1000 250` (앞 1,000장, 250장씩).

iverilog (참고):
```
iverilog -g2005 -DN_IMG=10 -o top.vvp sim_models/bram_models.v rtl/*.v tb/tb_npu_top.v && vvp top.vvp
iverilog -g2005 -DN_IMG=10 -DOREG_ON -o top2.vvp sim_models/bram_models.v rtl/*.v tb/tb_npu_top.v && vvp top2.vvp   (예전 ON 구성)
iverilog -g2005 -DTB_RD_LAT=1 -o ctrl.vvp rtl/npu_ctrl.v tb/tb_npu_ctrl.v && vvp ctrl.vvp
```

## 4. 팀 확인 필요 (불일치 목록, 11/14 갱신. 과제 공식 가이드가 팀 스펙보다 우선)
| # | 블록 | 내용 | 지금 처리 | 결정 필요 |
|---|---|---|---|---|
| 1 | B | **(가이드 p.9로 OFF 확정)** B의 11/12 IP는 WMEM·BMEM Primitives Output Register가 ON(읽기 지연 2). 가이드는 "should be disabled" | D·어댑터·top 반영 완료 (RD_LAT=1). 내 스크립트는 IP를 OFF로 새로 만들어서 100장 일치 + 100MHz 충족(WNS +2.55 ns) 확인 | **B IP 재생성 필요**: wmem_bank0~3, bmem_128의 .xci에서 Primitives Output Register 끄고 다시 Generate. 그리고 memory_controller.v 214·216줄의 weight_valid/bias_valid가 req를 2클럭 늦춘 값이라 OFF로 바꾸면 데이터보다 1클럭 늦음 → 1클럭 지연으로 수정 제안 (통합에서는 이 valid를 안 써서 결과에 영향 없음) |
| 2 | B | WMEM이 4뱅크(뱅크 i = n%4 뉴런) 구조. 스펙과 11/10 카톡은 단일 32b × 117,056 | D가 4뱅크 주소도 같이 냄 (`o_wbank_addr`, `o_wbank_sel`). 4뱅크로 100장 일치 확인 | 4뱅크를 최종으로 할지. BRAM은 4뱅크 합계 RAMB36 104 + RAMB18 8 |
| 3 | B | 모듈 이름 memory_controller, 포트 clk/rst(active-high 동기) | 어댑터에서 변환 | 이름 규칙에 맞출지 |
| 4 | B | npu_mem_ctrl(외부 인터페이스, busy MUX, 읽기 MUX) 없음, WMEM·BMEM 외부 쓰기 불가(COE만) | 어댑터가 대신 함. 임시 주소 맵 `i_addr[19:17]`: 2 IMEM_A, 3 ACT_A, 4 ACT_B, 5 OMEM | 정식 npu_mem_ctrl을 누가 마무리할지, 주소 맵 확정. **가이드 p.3은 제출물에 "testbench and hex file for data import"를 요구** → 가중치를 테스트벤치가 hex로 써 넣는 구조가 필요한지(그러면 B의 wea=0 고정을 풀어야 함), COE 초기화로 괜찮은지 교수님 확인 |
| 5 | 스펙 | v0.2 메모리 맵(ACT_A 228줄 등), shift 10/9가 옛날 값. 6-2절 DONE 타이밍(o_done이 DONE 클럭에 1)도 11/15 D01 이후 다름 | handoff 11/12 + golden v2 기준으로 구현. o_done은 DONE 다음 엣지(busy=0과 같은 엣지)에 1 | 스펙 v1.0 갱신 |
| 6 | C | C_pe_array_final.zip은 clk/rstn, handoff_D/rtl은 i_clk/i_rstn | handoff 버전 사용 | 최종본 하나로 정리 |
| 7 | D | 이름 표에 없는 포트 추가: `o_rd_en`, `o_wbank_addr`, `o_wbank_sel` | — | 이름 규칙 표에 추가 |
| 8 | B | (해결) 합성·BRAM 사용량·타이밍 미확인 | 통합 상태로 합성·구현 완료(출력 레지스터 OFF 기준): BRAM 112/144 타일, 100MHz 충족 | B README의 "Vivado 강제 종료"가 메모리 부족이었는지 확인 (나도 병렬 8개로 돌렸을 때 IP 런이 죽었고 2개로 낮추니 해결) |
| 9 | B | IMEM_B(더블 버퍼용)를 아무도 안 씀 | 어댑터에서 req=0으로 묶음. 구현 단계에서 자동으로 지워짐 (RAMB18 13 → 12) | 더블 버퍼를 쓸지, 안 쓰면 IP를 뺄지 |
| 10 | B | WMEM·BMEM의 ena가 1로 고정 → ISSUE가 아닌 클럭에도 읽기가 일어남 | D가 주소를 항상 범위 안에 두도록 수정 (2절 마지막 줄) | ena를 req에 연결할지 (전력 절약). 지금도 동작은 맞음 |
| 11 | C | 곱셈 4개가 DSP가 아니라 LUT로 합성됨 (DSP 0개) | 그대로 둠. 타이밍 문제 없음 | 의도한 건지. 발표에서 "DSP 몇 개" 질문이 나오면 답할 숫자 |
| 12 | 공통 | IP가 2024.1에서 만들어짐, 내 PC는 2024.2 | 같은 설정으로 2024.2에서 새로 생성 (`run_sim.tcl`) | 팀 Vivado 버전, 최종 제출 프로젝트를 누구 PC에서 만들지 |
| 13 | 공통 | 핀 배치·I/O 지연 제약 없음 | 가이드 p.33과 같은 클럭 제약 한 줄만 넣음 (`constr/npu_top.xdc`) | 보드에 올릴 건지, 시뮬 + 합성 리포트까지인지 (가이드 1-39쪽에는 보드 요구 없음. 40쪽 이후는 못 봄) |
| 14 | 공통 | 테스트셋 정확도 (가이드 보고서 6번) | (11/15) MNIST 테스트셋 1만 장 전체로 측정: 결과는 맨 위 표와 3절 5번. golden 1만 장분은 `scripts/gen_golden_10k.py`로 생성 (용량이 커서 저장소에는 안 넣고 `build/golden_10k/`에 만듦, 약 32 MB) | 보고서에 1만 장 숫자를 쓸지, 제출 zip에 1만 장 hex를 넣을지 (입력 hex만 17.6 MB) |
| 15 | 공통 | 제출 zip 구성 (가이드 p.3-5) | rtl/에는 initial, delay, readmemh 없음 | `sim_models/`(iverilog 전용, initial/readmemh 포함)는 제출 zip에서 제외. reg 배열 SRAM 금지 규칙에도 걸림 |
