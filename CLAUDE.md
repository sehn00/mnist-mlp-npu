# CLAUDE.md : AISSD 2조 NPU 프로젝트 (팀 공용)

Claude Code가 이 저장소에서 작업할 때 읽는 팀 공용 안내. 개인 메모는 각자 `CLAUDE.local.md`(.gitignore됨)에 둘 것.
사람이 읽을 결과 요약과 실행 방법은 `README.md`가 기준.

## 프로젝트 한 줄
중앙대 "인공지능반도체시스템설계" 4인 팀 프로젝트. MNIST MLP(784-512-128-10)를 int8 NPU로 Verilog 설계.
Kria K26C (xck26-sfvc784-2LV-c), 100 MHz, Vivado 2024.2.

## 구조 (PE 4개, 입력 방향 타일링)
- 한 클럭에 "한 뉴런"의 입력 4개 × 가중치 4개 → 곱 4개(s16) → 덧셈 트리(s17, s18) → 누산기 1개(s32)
- 뉴런 하나 = ISSUE L클럭(FC1 196, FC2 128, FC3 32) → WAIT (RD_LAT+1)클럭 → GO 1클럭. **RD_LAT=1** (BRAM 출력 레지스터 OFF, 가이드 p.9)
- GO 클럭: A에 go, C에 acc_clr. GO 다음 클럭에 A가 o_we (FC1/FC2는 lane 3일 때만 4개 묶음, FC3는 매 뉴런 32b 점수)
- 메모리 흐름: FC1 IMEM_A → ACT_A, FC2 ACT_A → ACT_B, FC3 ACT_B → OMEM
- 수치: 입력 0-127, 가중치 int8 대칭(레이어별 스케일), bias/누산 int32, 재양자화 = ReLU 후 오른쪽 shift(버림) 후 0-127 포화
- **shift: FC1 11, FC2 7 (golden v2)**. 정수 정확도 99.30% (float 99.32%)

| 블록 | 모듈 | 담당 | 상태 |
|---|---|---|---|
| A 후처리 | npu_postproc | 조원1 | 단위 TB PASS |
| B 메모리 | memory_controller (스펙상 npu_mem_ctrl) | 조원2 | 메모리 단독 TB PASS. **11/12 IP는 WMEM/BMEM 출력 레지스터 ON(가이드 위반) → OFF로 재생성 필요** |
| C PE 배열 | npu_pe_array | 조원3 | 사진 0 뉴런 650개 골든 일치 |
| D 제어기 + top | npu_ctrl, npu_top | 조원4 | 출력 레지스터 OFF 구성으로 Vivado 통합 100장 일치 + 100MHz 충족 |

## 자료 우선순위 (위가 이김. 같은 줄 안에서는 최신이 이김)
1. **과제 공식 가이드** (교수님 슬라이드, 공개 저장소에는 없음. e-class에서 받을 것). 팀 스펙과 충돌하면 가이드가 이김. 요구사항 대조표: `docs/과제가이드_요구사항_체크.md`
2. 팀 최신 결정, handoff_D_1112, NPU_naming_rules(11/12), golden v2(11/10), A·B·C 11/12 원본(`team_originals/`)
3. 아키텍처 스펙 v0.2 (10/29-11/5, 공개 저장소에는 없음): 구조·타이밍 설명은 유효. **메모리 맵(ACT_A 228줄 등), shift 10/9는 옛날 값**
4. `docs/old/`: 10월 자료 (PE 16, 128b SRAM 등 폐기된 내용 포함). 참고만

## 가이드 핵심 규칙 (어기면 감점 위험)
- **BMEM(blk_mem_gen) Primitives Output Register는 끌 것** (p.9) → 모든 SRAM 읽기 지연 1클럭, RD_LAT=1. Native / Single Port RAM (p.8)
- **SRAM은 BMEM으로만**, reg 배열로 SRAM 만들기 금지 (p.5). BMEM 연결: ena = ~CEN, wea = ~WEN (p.12)
- **`initial`, `#delay`, `$readmemh`/`$readmemb`는 테스트벤치와 주어진 SRAM 파일에서만** (p.4-5). rtl/에는 없어야 함. `sim_models/bram_models.v`(iverilog 전용)는 제출 zip에서 뺄 것
- **타이밍 slack 양수: WNS와 WHS 둘 다** (p.5, p.37). XDC는 `create_clock -name i_clk -period 10 [get_ports i_clk]` (p.33)
- 제출 (p.3): 팀당 1개 zip = 설계한 .v/.sv 전부 + 테스트벤치 + 데이터 넣는 hex + 보고서(.docx, .pdf, 템플릿 변경 금지). 마감은 최종 발표 하루 전, 늦으면 0점
- 보고서 필수 10항목 (p.13): 블록도(전체 + 학생별 IP), 하드웨어 매핑·메모리 트랜잭션, 검증 방법 + 캡처, 파형 4장(SRAM 읽기/쓰기, 연산 시작/끝), 레이어별 정답 비교, 테스트셋 정확도, 구현 후 schematic(전체 + IP별), 구현 결과(Device 화면, 자원, 타이밍, **전력 breakdown**), 자체 평가, 팀원별 역할

## 폴더 지도
```
rtl/            합성 대상 6개
  npu_ctrl.v        D
  npu_top.v         top, parameter RD_LAT(기본 1)를 npu_ctrl과 npu_mem_ctrl에 전달
  npu_mem_ctrl.v    B 임시 어댑터 (D 작성): memory_controller.v를 수정 없이 감쌈 + 외부 인터페이스
  npu_postproc.v    A 원본 복사 (수정 금지)
  npu_pe_array.v    C 원본 복사, handoff_D 버전(i_clk/i_rstn) (수정 금지)
  memory_controller.v  B 원본 복사 (수정 금지)
tb/             tb_npu_ctrl.v (D 단위), tb_npu_top.v (통합, `N_IMG, `HEX_DIR, `OREG_ON, `ACC_ONLY, +IMG_BASE=n),
                review/npu_checker.v (매 클럭 검사기 A1~A15), review/tb_edge.v (예외 상황 12종)
sim_models/     bram_models.v : iverilog 전용 BRAM 모델. **Vivado에 넣지 말 것** (IP와 이름 충돌), **제출 zip에서도 뺄 것**
hex/            통합 TB용 golden (사진 100장) + iverilog용 .mem
coe/            BRAM 초기화 COE (B 원본 그대로)
constr/         npu_top.xdc : 클럭 한 줄 (핀 배치·I/O 지연 없음)
run_regress.sh  전체 회귀 (Git Bash, xvlog/xelab/xsim만). 11단계, 하나라도 FAIL이면 exit 1
run_sim.tcl     Vivado batch: vivado_sim/ 프로젝트 + BRAM IP 10개(출력 레지스터 OFF) 생성 → 두 TB 실행 → result.txt
run_impl.tcl    Vivado batch: 합성 + 구현 + 리포트. WNS/WHS ≤ 0이면 exit 1
scripts/        check_ip.py (IP 설정 검사), gen_golden_10k.py (MNIST 1만 장 golden 생성), run_accuracy.sh (1만 장 RTL 정확도), review/ (검수용 스크립트)
reports/        시뮬·합성·구현·전력·정확도 결과 (커밋 대상)
docs/           요구사항 체크, 이름 규칙, handoff 문서, 리뷰, 회의 확인 사항
team_originals/ 팀원이 보낸 원본 그대로. 읽기 전용
```

## 현재 상태 (2026-11-15)
- Vivado 2024.2 + 실제 blk_mem_gen IP, 모든 BRAM Primitives Output Register OFF, RD_LAT=1
  - tb_npu_ctrl PASS: GO 512/128/10, bias_we 650, start→done 119,009클럭
  - tb_npu_top: **사진 100장 FC1/FC2/FC3 골든 v2 비트 일치, 예측 100/100**, 장당 119,009클럭
  - 회귀 `run_regress.sh` 11단계 PASS (검사기 2억 8,462만 번 검사 에러 0, 합성 이미지 16/16, tb_edge 16 PASS)
  - 테스트셋 정확도 1만 장: 파이썬 정수 모델과 RTL 시뮬 모두 **9,930 / 10,000 = 99.30%** (RTL은 커밋 74c88dd 기준, FC3 점수 전부 golden 비트 일치)
  - 구현: **100MHz 충족, WNS +2.709 ns, WHS +0.031 ns**. LUT 1,183 / FF 283 / BRAM 112타일(144 중) / DSP 0. 전력 0.366 W (vectorless, Confidence Low)
- 아직 안 한 것: 핀 배치, I/O 지연 제약, post-route 시뮬레이션, 보드 동작, 보고서용 캡처
- 팀 확인 필요 목록: README 4절, `docs/회의_1117_확인사항.md`

## D 설계 요약
- FSM: IDLE → ISSUE → WAIT → GO → (ISSUE | LAYER | DONE). LAYER는 레이어 전환 1클럭(마지막 줄 쓰기와 첫 읽기 충돌 방지)
- o_valid = ISSUE를 RD_LAT클럭 지연, o_bias_we = k=0 ISSUE를 RD_LAT클럭 지연, o_oaddr = GO에서 계산해 1클럭 뒤(A o_we와 정렬)
- o_done은 DONE 상태를 끝내는 엣지에 1, 같은 엣지에 busy=0. **o_done=1이면 항상 busy=0** → o_done만 기다리고 바로 읽어도 됨
- i_start는 1클럭 펄스로 줄 것 (끝난 뒤까지 1이면 재시작). 외부 포트 주소는 줄 수 안에서만 (범위 검사 없음)
- WMEM 주소: o_waddr(스펙 단일 WMEM), o_wbank_addr/o_wbank_sel(B 4뱅크: 뱅크 = n%4, 주소 = wbank_base + (n/4)·L + k)
- 이름 규칙 표에 없는 D 포트: o_rd_en, o_wbank_addr, o_wbank_sel

## 규칙
- `team_originals/`와 rtl/의 A·B·C 복사본(npu_postproc.v, npu_pe_array.v, memory_controller.v)은 **수정 금지**. 고칠 게 보이면 수정안을 텍스트로 제안하고 README 4절에 추가
- 남이 올린 파일을 요청 없이 덮어쓰지 말 것. 수정 전에 무엇을 왜 바꾸는지 먼저 말하기
- 추측 금지: 로그, 파형, 골든 비교 결과를 근거로 말하고, 확인 못 한 건 확인 못 했다고 말하기
- 시뮬 결과가 바뀔 수 있는 수정 후에는 `bash run_regress.sh`로 전체 회귀 확인 (약 5분). Vivado 프로젝트 흐름까지 볼 때는 run_sim.tcl도
- 의미 있는 단계마다 커밋 (vivado_sim/, build/, logs/, *.log, *.jou 제외)
- 공개 저장소: 팀원 실명, 카톡 대화, 교수님 자료를 커밋하지 말 것 (역할은 조원1~4로 표기)

## 실행
- 전체 회귀: `bash run_regress.sh` (Git Bash, 100장, 약 5분. `bash run_regress.sh 10`은 빠른 확인). exit 0 = 전부 PASS. 처음에는 run_sim을 한 번 돌려 `vivado_sim/`(IP 모델)을 만들어야 함
- Vivado batch: `vivado -mode batch -source run_sim.tcl -log logs/run_sim.log -journal logs/run_sim.jou -notrace -tclargs 100` (logs/ 먼저 만들 것. IP 설정을 바꾼 뒤에는 `-tclargs 100 fresh`)
- 합성 + 구현: `vivado -mode batch -source run_impl.tcl -log logs/run_impl.log -journal logs/run_impl.jou -notrace` (시뮬을 먼저 한 번)
- Vivado 위치가 기본값(`E:\Xilinx\Vivado\2024.2\bin`)과 다르면 `VIVADO_BIN` 환경 변수. 파이썬은 `NPU_PYTHON` (`PYTHON`은 Vivado가 덮어써서 쓰지 말 것)
- 병렬 작업 수는 2 이하 (`run_impl.tcl`의 JOBS). RAM 16GB PC에서 8로 돌리면 IP 합성 런이 에러 없이 죽음
- 테스트셋 정확도 1만 장: `python scripts/gen_golden_10k.py` → `bash scripts/run_accuracy.sh` (약 2시간 반, 끊기면 같은 명령으로 이어서)
- iverilog: `iverilog -g2005 -DN_IMG=10 -o top.vvp sim_models/bram_models.v rtl/*.v tb/tb_npu_top.v && vvp top.vvp`
