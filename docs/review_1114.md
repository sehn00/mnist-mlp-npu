# 독립 검증 리뷰 · D 블록 + 통합 + B 어댑터 · 2026-11-14 ~ 15

대상: `rtl/npu_ctrl.v`, `rtl/npu_top.v`, `rtl/npu_mem_ctrl.v`, `tb/`, `run_sim.tcl`, `run_impl.tcl`
기준: 과제 가이드 PDF(1-39쪽), 스펙 v0.2, 이름 규칙(11/12), handoff_D_1112, README, CLAUDE.md
방식: 기존 "PASS" 기록은 믿지 않고 전부 다시 돌림. **`rtl/`은 한 줄도 안 바꿈** (`git diff f1f2343 -- rtl/`이 비어 있음). 새로 만든 건 `tb/review/`, `scripts/review/`, `reports/review/`뿐.

## 0. 요약

**전체 판정: 통과. D·top·어댑터에서 결과를 틀리게 만드는 버그는 못 찾았어.** 다만 "지금 테스트가 못 보는 구멍"과 "쓰는 쪽이 조심해야 하는 동작"이 있어.

| 심각도 | 뜻 | 개수 |
|---|---|---|
| 치명 | 결과가 틀리거나 가이드 위반 | **0** |
| 중요 | 지금 결과는 맞지만 버그를 놓칠 수 있는 구멍, 또는 감점 위험이 있어 팀 결정이 필요한 것 | **4** |
| 경미 | 동작은 맞고, 쓰는 쪽이 조심하거나 문서를 고치면 되는 것 | **6** |
| 참고 | 기록해 둘 것 | **10** |

다시 확인한 숫자 (전부 이번에 직접 돌린 결과)

| 확인한 것 | 결과 | 근거 |
|---|---|---|
| 원래 스크립트 `run_sim.tcl` 그대로 (10장) | 두 TB PASS, 시뮬레이터 경고 0 | `result.txt` (11/15 02:53 실행) |
| D 단위 TB (RD_LAT=1 / 2) | PASS, 119,009 / 119,659클럭 | `build/review/t0`, `ctrl_rd2` 로그 |
| 통합 TB 100장 + 매 클럭 검사기 | 100/100 비트 일치, 예측 100/100, **검사 2억 7,264만 번에 에러 0** | `build/review/top100_chk/xsim.log` |
| 골든 독립 확인 (.pt에서 다시 계산) | 가중치 117,056줄, bias 650줄, 사진 100장 FC1/FC2/FC3 전부 일치 (33항목 FAIL 0) | `scripts/review/golden_check.py` |
| 합성 이미지 16장 (포화, 레인별, 난수) | 16/16 비트 일치, 검사기 에러 0 | `build/review/stress/xsim.log` |
| 예외 상황 12종 (tb_edge) | 판정 15개 PASS, FAIL 0, 관찰 6개. 검사기 5,340만 번에 에러 0 | `build/review/edge/xsim.log` |
| 버그 주입 49종 | 기능 버그 42개 중 기존 TB가 39개 잡음. 못 잡은 3개(B01, A01, A06)는 이번에 추가한 검사가 잡음 | `reports/review/mutation_results.md` |
| 합성 후 넷리스트 시뮬 | 사진 2장 비트 일치 (장당 약 5분) | `build/review/net_synth/xsim.log` |
| 배선 후 넷리스트 시뮬 (지연 없음) | 사진 1장 비트 일치 | `build/review/net_impl_saif/xsim.log` |
| 배선 후 타이밍 시뮬 (SDF 지연 포함) | 사진 1장 **FAIL** (FC1 28/128, FC2 25/32, FC3 0/10). **설계 문제가 아니라 시뮬레이터(XSim)의 SDF 지연 적용 문제로 추정** (2-8 참고). 미해결, 과제 범위 밖. 타이밍 충족의 근거는 리포트(WNS·WHS 양수) | `reports/review/sdf_probe.txt`, `build/review/net_impl_time/xsim.log` |
| 타이밍 다시 읽기 | WNS +2.553 ns, WHS +0.054 ns, 최소 주기 약 7.45 ns = **약 134 MHz** | `reports/review/worst_path_by_block.txt` |

가장 먼저 볼 3가지
1. **골든 100장으로는 포화 회로가 한 번도 시험되지 않아** (R01). 100장에서 FC1/FC2 출력이 127을 넘는 경우가 0번이야. 포화를 없앤 버그를 넣어도 100장이 전부 통과해. → 합성 이미지 16장을 회귀에 넣으면 해결 (이미 만들어 뒀고 원본 RTL은 통과).
2. **`o_done`이 `o_busy`보다 1클럭 먼저 올라가** (R05). 그 1클럭 동안의 읽기와 start는 조용히 무시돼. 스펙 6-1을 글자 그대로("o_done = 1 기다리기 → 읽기") 따라 TB를 짜면 첫 읽기가 틀린 값이 나와. 지금 통합 TB는 `o_busy == 0 && o_done == 1`을 기다려서 문제없음.
3. **WMEM 4뱅크는 뉴런 4개를 동시에 계산할 수 있는 구조인데 지금은 1개만 써** (2단계 P1). A·B·C 파일을 안 고치고 D·top·어댑터만 바꿔서 약 **3.9배** 빨라질 수 있어. 팀 결정이 필요해.

---

## 1. 발견 사항

심각도 순서. "재현"의 명령은 전부 저장소 루트에서 Git Bash로 실행 (5절 참고).

| ID | 심각도 | 위치 | 내용 | 근거 | 재현 | 수정 제안 |
|---|---|---|---|---|---|---|
| R01 | 중요 | golden hex 100장, `tb/tb_npu_top.v` | **포화(0~127 clamp)가 통합 테스트에서 한 번도 안 일어남.** 100장의 FC1 출력 최댓값 52, FC2 출력 최댓값 40. A의 포화 회로와 "큰 누산값" 경로가 미검증 | `golden_check.py` 출력 "포화(>127)된 출력: FC1 0 / 51200, FC2 0 / 12800". 뮤턴트 A01(포화 기준 127→1000), A06(포화 값 127→126)이 **golden 100장을 전부 통과**. 합성 이미지 16장에서는 둘 다 FAIL | `python scripts/review/golden_check.py`, `bash scripts/review/run_mutants.sh A01 A06` | `scripts/review/gen_stress.py`가 만드는 합성 이미지 16장(포화 FC1 24번, FC2 1번 발생)을 회귀에 추가. 원본 RTL은 16/16 통과. A 담당(조원1)에게도 공유 |
| R02 | 중요 | `tb/tb_npu_top.v` (검사 누락), 대상 `rtl/npu_mem_ctrl.v:64,80-97` | **"busy 중 외부 접근 무시"를 기존 TB가 검사하지 않음.** TB가 연산 중에는 외부 포트를 안 건드림 | 뮤턴트 B01(busy 중 외부 쓰기가 IMEM으로 들어가게 함)이 **golden 100장을 전부 통과**. `tb_edge`에서는 FAIL (검사기 에러 108,746건). 새 `tb_edge` S04는 원본 RTL에서 busy 중 쓰기+읽기 39,663쌍을 넣고도 결과·IMEM이 그대로임을 확인 | `bash scripts/review/run_mutants.sh B01` | `tb/review/tb_edge.v` + `npu_checker.v`를 회귀에 추가 (검사 A10) |
| R03 | 중요 | golden hex 100장 | **입력 첫 줄·마지막 줄에 둔감.** MNIST는 테두리가 0이라 FC1의 줄 0과 줄 195는 100장 전부 0. FC1·FC2 출력도 92%가 0 (FC2 입력 줄 0이 0이 아닌 사진은 11장, FC3는 20장) | 뮤턴트 D06(`o_valid` 1클럭 늦음 = 뉴런마다 줄 0을 빼먹음)이 **사진 2장에서는 통합 TB 통과**. 10장이면 8/10 (FC3에서만 걸림), 100장이면 75/100 | `bash scripts/review/run_mutants.sh D06` | R01과 같음 (합성 이미지는 모든 줄에 값이 있어서 바로 걸림). 통합 TB는 최소 10장 이상으로만 돌릴 것 |
| R04 | 중요 (팀·교수님 결정) | `rtl/memory_controller.v:86-87, 127-128`, `rtl/npu_mem_ctrl.v:20` | **가중치·bias를 외부 포트로 넣을 수 없음** (COE 초기화 전용, `ena = 1'b1`, `wea = 1'b0` 고정). 가이드 p.3은 "testbench and hex file for data import", 스펙 3절 주소 맵은 0 = WMEM 쓰기, 1 = BIAS 쓰기 | `tb_edge` S11: 번호 0/1에 쓰고 읽으면 0이 나오고 가중치는 그대로. README 4절 #4, #10과 같은 항목이지만 감점 위험이 있어 다시 올림 | `build/review/edge/xsim.log`의 S11 줄 | 교수님께 "COE 초기화 허용 여부" 확인. 허용 안 되면 B가 `wea`를 열고 TB가 117,706줄(가중치 117,056 + bias 650)을 쓰는 구조로 (시뮬 시작에 12만~24만 클럭 추가, 한 번만) |
| R05 | 경미 | `rtl/npu_ctrl.v:173, 190-192, 220` | **`o_done`이 `o_busy`보다 1클럭 먼저 1이 됨** (DONE 상태 클럭: done = 1, busy = 1). 이 클럭의 외부 읽기와 `i_start`는 무시됨. 스펙 6-2·6-5 표와는 일치하지만 스펙 6-1의 TB 순서("o_done = 1까지 기다리기 → 읽기")를 그대로 따르면 첫 읽기가 틀림 | `tb_edge` S12: done 직후 읽기 → `0a020000` (정답 `00000000`), 한 번 더 읽으면 정답. S07: DONE 클럭의 start 1클럭은 무시됨 | `build/review/edge/xsim.log`의 S07, S12 줄 | (a) 문서·TB 규칙으로 "`o_busy == 0 && o_done == 1`을 기다릴 것" 명시 (tb_npu_top은 이미 그렇게 함), 또는 (b) `o_done`을 IDLE로 돌아갈 때 올리기 (스펙 6-2 표도 같이 수정) |
| R06 | 경미 | `rtl/npu_ctrl.v:132-143` | **`i_start`를 계속 1로 두면 끝나자마자 다시 시작함** (레벨로 받음). 몇 클럭 유지는 문제없음(S03), 끝날 때까지 유지하면 무한 반복 | `tb_edge` S08 "re-triggered". 결과 값은 같음 | 같은 로그의 S08 줄 | 스펙대로 "1클럭 펄스"를 지키면 문제없음. 튼튼하게 하려면 상승 엣지 검출 1비트 추가 |
| R07 | 경미 (문서) | `README.md:41` | README의 "critical warning 0개"는 **로그 기준으로만 맞음.** 구현 후 DRC 리포트에는 Critical Warning 2건: NSTD-1(I/O 표준 미지정), UCIO-1(핀 위치 미지정). 82개 포트 전부 해당. 이 상태로는 비트스트림을 못 만듦 | `reports/review/drc_routed.rpt` | `grep -A3 "Critical Warning" reports/review/drc_routed.rpt` | README 문구를 "로그 critical warning 0개, DRC는 핀 미지정 2건"으로. 보드에 올릴 거면 핀 제약 필요 (README #13) |
| R08 | 경미 | `tb/tb_npu_ctrl.v:80`, `tb/tb_npu_top.v:104,134` | (1) `tb_npu_ctrl`에 타임아웃이 없음: `o_done`이 안 올라오면 시뮬이 안 끝남. (2) `tb_npu_top`은 클럭 수를 출력만 하고 검사하지 않음 → go가 1클럭 늦는 뮤턴트 D11(장당 119,659클럭)이 통합 TB 통과 | 뮤테이션 표 D11: unit FAIL, top PASS, 검사기 1,302건 | `bash scripts/review/run_mutants.sh D11` | TB에 타임아웃과 `cycles == 119009` 검사 추가 |
| R09 | 경미 | `rtl/npu_mem_ctrl.v:82,85-86,90-91,95-96` | 외부 포트 주소 처리: (1) 범위 검사 없음. IMEM 주소 196~255에 접근하면 IP 모델이 경고를 내고 읽은 값은 X (2) 윗주소 비트 `i_addr[16:8]` 무시 → 0x100에 쓰면 줄 0이 바뀜 (3) 주석은 ACT_A/ACT_B/OMEM이 "읽기"인데 외부 쓰기도 됨 | `tb_edge` S11 관찰 3줄 + `blk_mem_gen ... Address c8 is outside range` 경고 3줄. 합성 경고 Synth 8-7129 (i_addr[16:8] 안 씀) | 같은 로그의 S11 줄 | 정식 npu_mem_ctrl을 정할 때 주소 맵과 같이 결정. 최소한 README에 "주소는 줄 수 안에서만" 명시 |
| R10 | 경미 | `rtl/npu_mem_ctrl.v:172-185` | `o_dout`이 busy 중에도 내부 메모리 출력을 그대로 내보냄 (`i_addr[19:17]`이 가리키는 메모리). 그리고 읽은 값이 유지되지 않음: 선택 레지스터가 `i_cen`과 상관없이 매 클럭 바뀜 → "주소 준 다음 클럭"에만 유효 | `tb_edge` 끝의 `[CHK] FINAL ... o_dout changed while busy 413596 clk` | `grep FINAL build/review/edge/xsim.log` | 기능 문제는 없음. 깔끔하게 하려면 선택 레지스터에 enable(`w_ext_en`)을 걸기 |
| R11 | 참고 | `rtl/npu_ctrl.v:231` | 스펙 6-2 표는 "start 때 acc_clr 1회"인데 D는 GO 클럭에만 `o_acc_clr`를 냄. IDLE에서는 누산기가 항상 0(리셋 직후 또는 마지막 GO 뒤)이라 결과는 같음 | `tb_edge` S05a~d (연산 중 리셋 4가지 시점 후 재시작) 전부 골든 일치 | - | 그대로 둬도 됨. 스펙 v1.0에 표현만 맞추기 |
| R12 | 참고 | `rtl/npu_top.v:37,47`, `rtl/npu_ctrl.v:78,222` | `o_waddr`(단일 WMEM 주소)는 top에서 아무 데도 안 감. 합성에서 `r_w_ptr` 17비트가 지워짐. 지금은 TB·검사기의 기준 주소로만 쓰임 | 합성 후 D의 FF 60개. 뮤턴트 D24(o_waddr + 1)는 통합 TB 통과 | - | 4뱅크가 최종이면 그대로 둬도 비용 0. 보고서 블록도에는 "미연결"로 표시 |
| R13 | 참고 (C) | `rtl/npu_pe_array.v:1` | C 파일에 `` `timescale``이 없음 → xelab 경고 XSIM 43-4099. 지연을 안 써서 결과에는 영향 없음 | `build/review/base_top/xelab.log` | `grep 43-4099 build/review/base_top/xelab.log` | 조원3에게 전달 (맨 위에 `` `timescale 1ns / 1ps`` 한 줄) |
| R14 | 참고 | `rtl/npu_ctrl.v:33`, `rtl/npu_mem_ctrl.v:158-161` | `RD_LAT` 값 검사가 없음. D는 1~3, 어댑터는 1 또는 2만 맞게 동작 | 코드 | - | B가 OFF로 확정하면 어댑터의 RD_LAT = 2 경로(합성 때 지워지는 레지스터 3개)를 정리 |
| R15 | 참고 | `constr/npu_top.xdc`, 전 블록의 `negedge i_rstn` | 리셋 동기화기 없음 + 입력 47개·출력 34개가 타이밍 제약 없음 → "리셋 해제 직후 바로 start"는 RTL 시뮬에서는 통과(S01)지만 실제 보드에서는 보장 안 됨 | `reports/review/check_timing.rpt` (no_input_delay 47, no_output_delay 34) | - | 시뮬 + 리포트까지만 제출이면 그대로. 보드에 올리면 I/O 지연 제약과 리셋 동기화 필요 |
| R16 | 참고 | golden | 가중치 정수화에서 반올림 경계(.5)까지 1.8e-7 떨어진 값이 하나 있음. float32로 계산하면 1이 달라질 수 있음 | `golden_check.py` 출력 첫 부분 | - | hex는 팀 것과 일치하니 그대로 사용. 다시 만들 때는 같은 스크립트(float64)로 |
| R17 | 참고 (미확인) | `hex/input_act_a.hex` | 이 PC에 MNIST 원본이 없어서 "픽셀 >> 1" 변환과 1만 장 정확도 99.30%는 독립 확인 못 함. 입력 hex 100장을 받은 그대로 써서 그 뒤만 확인 | - | - | 필요하면 MNIST를 받아서 확인 (4절 결정 6) |
| R18 | 참고 (B) | `rtl/memory_controller.v:86,95,104,113,127` | WMEM 4뱅크와 BMEM의 `ena`가 `1'b1` 고정 → 매 클럭 4뱅크를 다 읽고 3개는 버림. 가이드 p.12의 "~CEN = ena" 모양과도 다름. README #10과 같은 항목 | 2단계 P2 참고 | - | 2단계 P2 |
| R19 | 참고 (B) | `rtl/memory_controller.v:213-216` | `weight_valid`, `bias_valid`가 req를 2클럭 늦춘 값 (출력 레지스터 OFF에서는 1클럭이 맞음). 통합에서는 안 씀. README #1과 같음 | 코드 | - | B가 IP를 OFF로 다시 만들 때 같이 수정 |
| R20 | 참고 | 합성·구현 로그 | 경고 분류는 2절 2번 표. 무시하면 안 되는 것은 R07 하나 | - | - | - |

---

## 2. 1단계 항목별 결과

### 2-1. 코드 리뷰 (npu_ctrl, npu_top, npu_mem_ctrl)

한 줄씩 읽고 스펙 6절 타이밍 표와 대조한 결과. "c0 = 뉴런의 첫 ISSUE 클럭"으로 적으면 RD_LAT = 1일 때:

| 클럭 | D 상태 | 일어나는 일 | 코드 위치 |
|---|---|---|---|
| c0 ~ c(L-1) | ISSUE | 주소 k 내보냄 (`o_xaddr = r_k`, 뱅크 주소 +1) | `npu_ctrl.v:145-160` |
| c1 ~ cL | | `o_valid = 1` (ISSUE를 1클럭 늦춤), B에서 x·w 나옴 | `:212, 230` |
| c1 | | `o_bias_we = 1` (k = 0 ISSUE를 1클럭 늦춤), A가 bias 저장 | `:213, 232` |
| cL, c(L+1) | WAIT | `r_wait_cnt` 0 → 1. 곱 레지스터와 누산기가 따라옴 | `:162-165` |
| c(L+2) | GO | `o_go = o_acc_clr = 1`. 마지막 valid(cL)의 정확히 2클럭 뒤 | `:167-178, 231, 233` |
| c(L+3) | 다음 ISSUE / LAYER / DONE | A의 `o_we`, `o_oaddr`(GO에서 계산해 1클럭 늦춤) | `:168, 227` |

확인한 것 (전부 문제없음)
- **FSM 전이**: IDLE→ISSUE→WAIT→GO→(ISSUE/LAYER/DONE), DONE→IDLE. 스펙 6-2 그림과 같음. 쓰지 않는 상태값 6, 7은 IDLE로 (`:194`). 합성 로그에 FSM 인식·`sequential` 인코딩 확인.
- **카운터 경계**: `w_last_k = (r_k == L-1)` 195/127/31, `w_last_n = (r_n == N-1)` 511/127/9 (`:111-112`). 검사기 A7이 뉴런마다 valid 개수 = L인지, A13이 GO 512/128/10을 100장 내내 확인.
- **비트 폭**: `r_n` 10b(최대 511), `r_k` 8b(195), `r_w_ptr` 17b(마지막 ISSUE 뒤 117,056 < 131,072), `r_wb_ptr` 15b(최대 29,279), `r_b_ptr` 10b(끝난 뒤 650), `r_oaddr` 8b. 넘치는 곳 없음. 뱅크 포인터 되돌림 `r_wb_ptr - L + 1`(`:151`)은 그 시점에 `r_wb_ptr >= L-1`이라 음수가 안 됨.
- **리셋**: D·A·C·어댑터의 모든 레지스터가 `negedge i_rstn` 비동기 리셋. B의 valid 레지스터만 동기 리셋(`rst = ~i_rstn`), 통합에서는 안 씀. BRAM 내용은 리셋 안 됨 → 연산 중 리셋 후 재시작해도 IMEM이 남아 있어 결과가 맞음 (S05).
- **지연 정렬(RD_LAT)**: valid·bias_we는 시프트 레지스터의 `[RD_LAT-1]` 비트, WAIT는 `RD_LAT + 1`클럭, 어댑터의 뱅크/bias/x 선택 신호도 같은 만큼 늦춤 (`npu_mem_ctrl.v:151-161`). RD_LAT = 2도 다시 돌려 봄: D 단위 PASS(119,659클럭), 행동 모델 `OREG_ON` 2장 PASS + 검사기 에러 0.
- **레이어 전환**: LAYER 1클럭 동안 `r_layer`가 아직 이전 값이라 A의 마지막 쓰기가 이전 레이어 출력 메모리로 감 (`:180-188`). 검사기 A8이 "쓰기 클럭의 layer = 그 뉴런의 레이어"를 매번 확인.
- **읽기/쓰기 충돌**: 레이어마다 읽는 메모리와 쓰는 메모리가 다르고(IMEM→ACT_A→ACT_B→OMEM), 전환 때는 LAYER가 1클럭 벌려 줌. 검사기 A9가 "같은 메모리를 같은 클럭에 읽고 쓰지 않음"을 전 구간 확인, 위반 0.
- **4뱅크 주소**: 포인터 +1, 뉴런 마지막 줄에서 lane ≠ 3이면 묶음 시작으로 되돌림. 검사기 A5가 valid 클럭마다 `w == 단일 WMEM hex[o_waddr]`를 비교 → 4뱅크 매핑과 뱅크 선택이 스펙의 단일 주소와 같은 값을 읽는다는 걸 100장 × 117,056줄 전부 확인. 주소 범위(A1)도 매 클럭 0~29,279.

스펙·이름 규칙과 다른 점 (전부 README 4절에 이미 있거나 위 표에 넣음)
- 외부 주소 맵: 스펙은 0 WMEM, 1 BIAS, 2 ACT_A, 3 ACT_B, 4 OMEM. 어댑터는 2 IMEM_A, 3 ACT_A, 4 ACT_B, 5 OMEM (README #4, R04).
- 스펙 B 포트 이름(`i_w_addr`, `i_x_sel`, `i_wb_*`)과 다름. 이름 규칙 11/12 표(`waddr`, `xaddr`, `baddr`, `oaddr`, `layer`)를 따랐고, 표에 없는 `rd_en`, `wbank_addr`, `wbank_sel`, `busy` 선이 추가됨 (README #7).
- R05(done/busy 1클럭 차이), R11(start 때 acc_clr).

### 2-2. 연결 검증

top의 선과 포트 폭 대조 (`npu_top.v:32-75`). 전부 폭 일치.

| 선 | 폭 | 보내는 쪽 | 받는 쪽 | 비고 |
|---|---|---|---|---|
| x, w | 32 | B `o_x`, `o_w` | C `i_x`, `i_w` | |
| bias | 32 | B `o_bias` | A `i_bias` | BMEM 128b에서 lane으로 고른 32b |
| acc | 32 | C `o_acc` | A `i_acc` | |
| we, wdata | 1, 32 | A `o_we`, `o_wdata` | B `i_we`, `i_wdata` | |
| valid, acc_clr | 1 | D | C | |
| bias_we, go, relu_en, fc3 | 1 | D | A | |
| lane, shift | 2, 5 | D | A | |
| rd_en | 1 | D `o_rd_en` | B `i_rd_en` | 이름 규칙 표에 없음 |
| wbank_addr, wbank_sel | 15, 2 | D | B | 이름 규칙 표에 없음 |
| xaddr, baddr, oaddr, layer | 8, 10, 8, 2 | D | B | oaddr[7]은 B에서 안 씀 |
| waddr | 17 | D `o_waddr` | (없음) | R12 |
| busy | 1 | D `o_busy` | B `i_busy`, top `o_busy` | |
| 외부 포트 | 1, 1, 20, 32, 32 | top `i_cen, i_wen, i_addr, i_din` / `o_dout` | B | |

어댑터 → memory_controller: `weight_addr` 15, `bias_addr` 8(= `i_baddr[9:2]`), `act_a_addr` 7, `act_b_addr` 5, `imem_a_addr` 8, `omem_addr` 4, 데이터 32/128. 전부 일치. IMEM_B는 req = 0으로 묶음.

경고 분류 (합성 `synth_1/runme.log` 34줄, 구현 `impl_1/runme.log` 0줄, 시뮬 elaboration)

| 경고 | 개수 | 내용 | 판단 |
|---|---|---|---|
| Synth 8-7129 | 20 (포트 10개 × 2번) | 어댑터의 `i_addr[16:8]`, `i_oaddr[7]`을 안 씀 | 무시 가능 (의도). 단 주소 겹침은 R09 |
| Synth 8-6014 | 3 | `r_wsel_d2`, `r_bsel_d2`, `r_x` 제거 | 무시 가능 (RD_LAT = 2 전용 레지스터) |
| Timing 38-316 | 10 | BRAM IP를 따로 합성할 때 클럭 20 ns, 실제 10 ns | 무시 가능. 최종 타이밍은 10 ns로 다시 분석됨 |
| Synth 8-7080 | 1 | 병렬 합성 조건 미달 | 무시 |
| Vivado 12-13340, 12-7122, Wavedata 42-489 | 2, 1, 3 | GCC 경로, 증분 컴파일 기준 없음, 큰 배열 파형 표시 | 무시 (도구 안내) |
| XSIM 43-4099 | 2 | C 파일에 timescale 없음 | R13 |
| DRC NSTD-1, UCIO-1 (Critical) | 2 | I/O 표준·핀 위치 미지정 | **무시하면 안 됨: R07** (보드에 올릴 때) |
| Methodology TIMING-18 | 90 | 입출력 지연 제약 없음 | R15 |

없는 것: 폭 불일치(Synth 8-689), latch 추론(8-327), multi-driven(8-6859, 8-3352), black box, `check_timing`의 no_clock / latch_loops / unconstrained_internal_endpoints 전부 0. 상수로 구동되는 포트는 B 원본의 WMEM·BMEM `ena = 1`, `wea = 0`, `dina = 0`과 어댑터의 IMEM_B 묶음뿐 (의도).

### 2-3. 가이드 규칙 점검

| 규칙 (쪽) | 결과 | 근거 |
|---|---|---|
| `initial`, `#지연`, `$readmemh/b`는 TB에서만 (p.4-5) | 통과 | `grep -nE '\binitial\b|\$readmem|#[0-9]' rtl/*.v` 결과 없음 |
| SRAM은 BMEM으로만, reg 배열 금지 (p.5) | 통과 | rtl/에 reg 배열 선언 없음. 메모리 10개 전부 `blk_mem_gen` 인스턴스 (`memory_controller.v:84-193`) |
| Primitives Output Register OFF (p.9) | 통과 (내 스크립트가 만든 IP) | 생성된 .xci 10개와 B 원본 .xci 대조: 차이는 출력 레지스터(WMEM·BMEM true → false)와 COE 경로뿐. B 원본은 아직 ON (README #1) |
| Native, Single Port RAM (p.8) | 통과 | .xci: `Interface_Type Native`, `Memory_Type Single_Port_RAM`, `WRITE_FIRST`, `Use_ENA_Pin` |
| ~CEN = ena, ~WEN = wea (p.12) | 외부 포트는 통과, WMEM·BMEM은 모양이 다름 | 어댑터: `ena = !busy && !cen && (번호 일치)`, `wea = ena && !wen` (`npu_mem_ctrl.v:64-65, 80-97`). WMEM·BMEM은 `ena = 1`, `wea = 0` 고정 (R18) |
| slack 양수: WNS, WHS (p.5, p.37) | 통과 | +2.553 / +0.054 ns. 배선 결과를 다시 열어서 확인 (`reports/review/worst_path_by_block.txt`) |
| XDC (p.33) | 통과 | `constr/npu_top.xdc` 한 줄이 가이드와 같음 |
| 제출물: testbench와 hex file for data import (p.3) | **팀 확인 필요** | R04 |
| 제출 zip | 주의 | `sim_models/`는 빼야 함 (initial, readmemh, reg 배열). `tb/review/`는 테스트벤치라 넣어도 규칙 위반은 아님 |

### 2-4. 골든 독립 확인

`scripts/review/golden_check.py`: 팀의 `golden_v1.py`를 쓰지 않고 `.pt`를 직접 풀어서(torch 없이) 다시 계산.
- 정수화: 입력 q = 픽셀 >> 1 기준으로 Normalize를 FC1에 접어 넣고, 레이어별 `127 / max|W|`로 int8, bias는 누산기 스케일 int32, 다음 레이어 스케일은 `/ 2^shift` (11, 7).
- 추론: 하드웨어 순서 그대로 (줄 단위, 레인 4개 곱 → 덧셈 2단 → 누산) → + bias → ReLU → `>>`(버림) → 0~127 포화 → 4개 묶기.

결과: **33개 항목 전부 일치.** 가중치 117,056줄(handoff `wmem.hex`, golden_v2 `weight.hex`, COE 4뱅크를 D의 주소 식으로 풀어서, `hex/*.mem`), bias 650줄(+ 128b COE 163줄), 사진 100장의 FC1 12,800줄 / FC2 3,200줄 / FC3 1,000줄, 예측 100/100, 단계별 정답(사진 0~9의 누산값, +bias).

같이 알게 된 것
- 비트 폭 여유: 곱 최대 16,129(s16), 덧셈 1단 29,972(s17), 2단 49,149(s18), 누산 최대 369,257(2^18.5). 실제 가중치로 계산한 최악 입력 상한도 1,282,427(2^20.3)이라 s32는 넉넉함.
- 가중치 범위 -127~66 / -127~70 / -127~89 (−128 없음). 안 쓰는 뱅크 주소 64개(뱅크 2·3의 29,248~29,279)는 0.
- 100장에서 포화 0번, FC1 출력의 92.1%와 FC2 출력의 92.6%가 0 (R01, R03).
- 확인 못 한 것: 입력 hex 자체(MNIST → 0~127)와 1만 장 정확도 (R17).

### 2-5. 예외 상황 테스트 (`tb/review/tb_edge.v` + 검사기)

| 시나리오 | 결과 |
|---|---|
| S01 리셋 중에 이미지 쓰기 → 리셋을 푼 바로 그 클럭에 start | PASS (리셋 중 외부 쓰기도 BRAM에 들어감) |
| S02 연산 중 `i_start` 재입력 124번 (997클럭마다, WAIT/GO/LAYER 상태에 맞춰, 300클럭 연속) | PASS, 119,009클럭 그대로 |
| S03 `i_start` 5클럭 유지 | PASS |
| S04 연산 중 외부 쓰기+읽기 39,663쌍 (모든 SRAM 번호) | PASS, IMEM 196줄 그대로 |
| S05a~d 연산 중 리셋 (FC1 중간 / FC2 중간 + 이미지 교체 / FC3 끝 직전 / 쓰기 클럭 한가운데) 후 재시작 | 전부 PASS |
| S06a busy가 내려간 첫 클럭에 start, S06b 마지막 줄 쓰기와 같은 클럭에 start | PASS |
| S09 busy가 내려간 첫 클럭에 OMEM 9 읽기 | PASS |
| S10 cen을 계속 0으로 두고 연속 쓰기 / 연속 읽기 / 쓰기 다음 클럭 읽기 | PASS |
| S11 없는 번호·범위 밖·겹치는 주소 접근 후 정상 연산 | PASS (가중치 그대로) |
| S07 DONE 클럭의 start | 관찰: 무시됨 (R05) |
| S12 done 직후 읽기 | 관찰: 첫 읽기 무시됨 (R05) |
| S08 start를 끝난 뒤까지 유지 | 관찰: 다시 시작함 (R06) |
| S11 주소 관찰 3건 | R04, R09 |

합계: 판정 15개 PASS, FAIL 0, 관찰 6개. 연산 21번 동안 검사기 53,398,341번 검사, 에러 0.

### 2-6. 어서션 (`tb/review/npu_checker.v`)

기존 TB를 고치지 않고 시뮬레이션에 "두 번째 top"으로 같이 올리는 검사기. D 내부 레지스터는 안 보고 블록 경계 신호만 봄. 기대값은 검사기가 따로 세는 (레이어, 뉴런, 줄) 카운터와 그림자 메모리로 만듦.

| ID | 매 클럭 검사하는 조건 | 요청 항목 |
|---|---|---|
| A1, A2 | WMEM 뱅크 주소 ≤ 29,279, BMEM 주소 ≤ 162 (ISSUE가 아닌 클럭 포함) | wbank 주소 ≤ 29,279 |
| A3 | 읽기 클럭의 layer, xaddr, waddr, wbank_addr, wbank_sel, baddr = 기대값. BRAM 포트에도 그 주소가 감 | |
| A4, A5 | valid = rd_en을 RD_LAT 늦춘 것. valid 클럭의 w = 단일 WMEM hex 값, x = 그림자 메모리 값 | |
| A6 | bias_we는 뉴런당 정확히 1번, 그때 bias = bias hex 값 | 뉴런당 bias_we 1번 |
| A7 | go는 마지막 valid의 정확히 2클럭 뒤, valid 개수 = L, acc_clr = go, lane/shift/relu/fc3 | go는 마지막 valid 2클럭 뒤 |
| A8 | o_we는 go 다음 클럭에만, 그 클럭의 layer·oaddr·wdata = 기대값 (wdata는 검사기가 후처리를 따로 계산) | |
| A9 | 쓰기 주소 범위(127 / 31 / 9), 같은 메모리를 같은 클럭에 읽고 쓰지 않음 | oaddr 범위, 동시 읽기/쓰기 없음 |
| A10 | busy 동안 BRAM 포트(ena, wea)는 내부 신호만으로 결정 | busy 중 외부 접근 무시 |
| A11 | 외부 읽기: 주소 준 다음 클럭의 o_dout = 그림자 메모리 값 | |
| A12 | start/busy/done 규칙 | |
| A13 | 연산이 끝나면 go 512/128/10, 쓰기 128/32/10, valid 117,056, bias_we 650, 줄마다 정확히 1번 쓰기, 119,009클럭 | |
| A14 | 제어 신호와 쓰이는 데이터에 X 없음 | |
| A15 | go 클럭의 acc, acc + bias = 파이썬 독립 모델 값 | |

결과: golden 100장 272,643,486번, 합성 이미지 16장 43,620,846번, tb_edge 53,398,341번 검사에서 **에러 0.** 검사기 자체가 버그를 잡는지는 2-7에서 확인: golden 2장 시뮬에 붙였을 때 기능 버그 42개 중 39개에서 에러를 냄. 못 낸 3개(B01, A01, A06)는 golden 사진으로는 그 상황(busy 중 외부 접근, 포화)이 아예 안 생기는 것들이고, `tb_edge`와 합성 이미지에서는 잡힘.

### 2-7. 테스트벤치 신뢰성 (버그 주입)

`rtl/` 복사본에 버그를 하나씩 넣은 49종 (D 28, 어댑터 10, A 6, C 5). 전체 표: `reports/review/mutation_results.md`.

돌린 것: (1) 기존 `tb_npu_ctrl` (D 뮤턴트만), (2) 기존 `tb_npu_top` golden 2장 + 검사기, (3) 2장을 통과한 것만 golden 10장·100장, 합성 이미지 16장, `tb_edge`.

| 분류 | 개수 | 기존 TB 결과 |
|---|---|---|
| 기능 버그 (결과가 틀려야 하는 것) | 42 | **39개 잡음.** D 23개 중 `tb_npu_ctrl`이 22개, `tb_npu_top` 2장이 42개 중 38개 |
| 결과는 같고 타이밍·안 쓰는 출력만 다른 것 (D08, D11, D24, D28) | 4 | `tb_npu_ctrl`이 4개 다 잡음. `tb_npu_top`은 전부 통과 (결과가 같으니 당연) |
| 동작이 완전히 같은 것 (D25, B10, C05) | 3 | 전부 통과 (정상. 못 잡는 게 맞음) |

기존 TB가 못 잡거나 약하게 잡은 것

| 뮤턴트 | 넣은 버그 | golden 2장 | 10장 | 100장 | 합성 16장 | tb_edge | 관련 |
|---|---|---|---|---|---|---|---|
| A01 | 포화 없음 (기준 127 → 1000) | 통과 | 통과 | **통과** | FAIL | 통과 | R01 |
| A06 | 포화 값 127 → 126 | 통과 | 통과 | **통과** | FAIL | 통과 | R01 |
| B01 | busy 중 외부 쓰기가 IMEM에 들어감 | 통과 | 통과 | **통과** | 통과 | FAIL | R02 |
| D06 | `o_valid` 1클럭 늦음 (줄 0을 빼먹음) | **통과** | FAIL (8/10) | FAIL (75/100) | FAIL | FAIL | R03 |
| D11 | go 1클럭 늦음 (장당 119,659클럭, 결과는 같음) | 통과 | - | - | 통과 | FAIL (검사기) | R08 |

읽는 법
- 기존 TB 두 개는 D의 주소·순서·타이밍 버그는 잘 잡아 (shift 값, L·N 경계, 주소 +1, lane 순서, 뱅크 선택, 레이어 설정, done/busy 전부 FAIL).
- 못 잡는 건 "golden 사진에서는 일어나지 않는 상황"뿐: 포화, busy 중 외부 접근. 그래서 R01, R02를 중요로 올렸어.
- `tb_npu_ctrl`은 D27(busy가 DONE 클럭에 미리 내려감)을 통과시킴. 이건 `tb_npu_top`이 잡음 (OMEM 9가 안 써짐). 두 TB가 서로 보완하고 있음.
- D26(`o_done`이 1클럭만 1)에서 `tb_npu_top`은 타임아웃으로 끝남 (4천만 ns 뒤). 타임아웃이 있어서 다행인 경우이고, `tb_npu_ctrl`에는 그게 없음 (R08).

### 2-8. 구현된 회로 검증

`scripts/review/netlist_export.tcl`로 합성·구현 결과에서 넷리스트를 뽑고(두 런 모두 `needs_refresh = 0`, 즉 지금 RTL과 일치), 기존 `tb_npu_top`으로 돌림. TB는 넷리스트에 parameter가 없어서 인스턴스 줄만 바꾼 복사본.

| 시뮬 | 넷리스트 | 지연 | 장수 | 결과 | 걸린 시간 |
|---|---|---|---|---|---|
| 합성 후 기능 | `npu_top_synth_funcsim.v` | 없음 | 2 | **2/2 비트 일치**, 예측 2/2, 장당 119,009클럭 | 준비(elaboration) 6분 + 시뮬 10분 7초 |
| 배선 후 기능 | `npu_top_impl_funcsim.v` | 없음 | 1 | **1/1 비트 일치**, 119,009클럭 | 시뮬 4분 42초 (스위칭 기록 SAIF도 같이 남김 → 3절 전력 분석에 사용) |
| 배선 후 타이밍 | `npu_top_impl_timesim.v` + SDF (느린 코너, 최대 지연) | 있음 | 1 | **FAIL** (FC1 28/128, FC2 25/32, FC3 0/10, 클럭 수는 119,009로 정상, 타이밍 위반 메시지 0건). 아래 "타이밍 시뮬 FAIL에 대해" 참고 | 준비 5분 반 + 시뮬 24분 27초 |

**타이밍 시뮬 FAIL에 대해 (미해결, 과제 범위 밖)**
- 결론: **설계 문제가 아니라 XSim 2024.2가 SDF의 클럭 배선 지연을 일부 플립플롭에 적용하지 못해서 생긴 시뮬레이터 문제로 추정.** 인스턴스 이름에 대괄호가 있는 FF(`r_valid_sr_reg[0]`, `acc_reg[*]` 등 대부분)에는 클럭 배선 지연(약 1.9 ns)이 안 들어가고, 대괄호가 없는 FF(`v1_reg`, `o_we_reg`, `o_done_reg`)에만 들어가. 그래서 시뮬 안에서만 두 무리 사이에 가짜 클럭 차이 1.9 ns가 생기고, 뒤쪽 3개가 값을 1클럭 일찍 잡아서 결과가 틀려져.
- 근거 1 (최소 실험): FDCE 4개에 똑같이 클럭 지연 2,000 ps를 준 SDF로 돌리면 대괄호 없는 2개는 엣지 +2.110 ns, 대괄호 있는 2개는 +0.110 ns에 바뀜. `tb/review/sdf_probe/`, `scripts/review/sdf_probe.sh`, 결과 `reports/review/sdf_probe.txt`.
- 근거 2 (실제 넷리스트): 같은 배선 후 넷리스트를 지연 없이 / 지연 넣고 앞 1,250클럭 파형 비교(`scripts/review/vcd_compare.py`). 지연을 넣은 쪽은 `valid`·`acc`·주소류가 핀 클럭 엣지 +1.16 ns, `v1`·`we`가 +3.03 ns에 바뀌고, `v1`과 `we`가 1클럭 일찍 올라감. SDF 파일 자체에는 두 FF 모두 같은 클럭 지연(1,886.9 ps)이 적혀 있음.
- 설계 쪽 근거: 정적 타이밍 분석은 모든 지연을 넣고 WNS +2.553 / WHS +0.054 ns (가이드 p.37이 요구하는 것), 지연 없는 배선 후 넷리스트는 비트 일치. 핀 기준 입출력 타이밍은 `reports/review/io_datasheet.rpt` (입력 setup 최대 2.3 ns, hold 최대 1.6 ns, `o_dout` 출력 지연 최대 9.0 ns).
- 안 한 것: XSim 옵션이나 SDF를 바꿔서 타이밍 시뮬을 통과시키는 것, Vivado 자체 타이밍 시뮬 흐름으로 재확인. "시뮬레이터 문제"라는 결론은 위 두 근거에 따른 추정이고, 통과하는 타이밍 시뮬로 확인한 건 아님.

- 넷리스트는 실제 BRAM primitive(RAMB36E2 106개, RAMB18E2 12개)와 LUT·FF로 풀린 회로라서, 여기서 맞으면 "합성·배치 과정에서 동작이 바뀌지 않았다"는 뜻이야. 가중치 초기값(COE)도 primitive 안에 제대로 들어간 게 확인됨.
- 타이밍 시뮬용 TB는 두 군데를 더 바꿨어: 리셋 해제를 negedge로, `o_dout` 읽는 시점을 negedge 4.5 ns 뒤(다음 posedge 0.5 ns 전)로. 실제 회로에서는 출력이 클럭 엣지에서 몇 ns 늦게 핀에 나오는데, 원래 TB는 엣지 5 ns 뒤에 읽어. 입출력 지연 제약이 없어서(R15) 그 5 ns 안에 나온다는 보장이 없기 때문이야. SDF 지연 주입은 성공 (`XSIM 43-3452 SDF backannotation was successful`).
- 장수를 늘릴 때 예상 시간: 지연 없는 넷리스트 100장은 약 8시간 (장당 약 4분 45초). RTL 시뮬(100장 2분 반)과 결과가 같은지만 보면 되므로 1~2장으로 충분하다고 봤어.

---

## 3. 2단계: 개선 여지 (조사만, 구현 안 함)

숫자의 근거: 자원은 구현 후 계층별 사용량(`reports/impl_utilization_hier.rpt`: A LUT 66 / FF 97, B 763 / 29, C 154 / 97, D 202 / 60), 타이밍은 `reports/review/worst_path_by_block.txt`, 전력은 배선 후 넷리스트로 사진 1장을 실제로 돌린 스위칭 기록(SAIF)을 넣은 `reports/review/power_summary.txt`.

전력 기준선 (지금 설계)

| 조건 | 합계 | 동적 | BRAM | I/O | Signals | Logic | Clocks | 정적 |
|---|---|---|---|---|---|---|---|---|
| vectorless (기존 `reports/impl_power.rpt`와 같은 조건, Confidence Low) | 0.367 W | 0.077 | 0.038 | 0.025 | 0.006 | 0.004 | 0.004 | 0.289 |
| **실제 스위칭 기록 (사진 1장, Confidence High)** | **0.360 W** | **0.071** | 0.040 | 0.021 | 0.005 | 0.002 | 0.004 | 0.289 |

→ 전력의 80%가 정적(칩이 켜져 있기만 해도 드는 전력)이라, 전력 자체보다 **연산 시간을 줄이는 쪽**이 장당 에너지에 훨씬 크게 듣는다. 지금 장당 에너지 = 0.360 W × 1.19 ms ≈ 428 µJ. 보고서 8번(전력)에는 Confidence High인 둘째 줄 숫자를 쓰는 것도 방법.

### 3-1. 개선안 표

| ID | 개선안 | 기대 효과 | 비용 | 위험 | 팀 결정 | 추천 |
|---|---|---|---|---|---|---|
| P1 | **뉴런 4개 병렬** (WMEM 4뱅크를 동시에 쓰고 C를 4개 둠) | 장당 119,009 → **약 30,259클럭 (3.93배)**. 1.19 ms → 0.30 ms, 초당 840장 → 약 3,300장. 장당 에너지 약 428 → 115 µJ. LUT 1,185 → 약 1,650, FF 283 → 약 580, BRAM·DSP 그대로 | D·top·어댑터 수정(전부 조원4 파일), TB 2개와 검사기 기대값 수정. **A·B·C 원본은 안 고침** | 중간 (일정, 보고서의 구조 설명이 "PE 4개"에서 "PE 4 × 4"로 바뀜) | 필요 | **조건부 추천** (평가에 속도가 들어가면) |
| P2 | WMEM·BMEM ena 게이팅 | **−0.008 ~ −0.012 W** (전체의 2~3%, 동적의 11~17%) | **B 원본 수정 필요** (`memory_controller.v`의 `.ena(1'b1)` 5곳) + 어댑터 | 낮음~중간 (enable 경로 여유 3.45 ns에 조건 하나 추가) | 필요 (B) | 낮은 우선순위. B에게 제안만 |
| P3 | WAIT/GO 3클럭을 다음 뉴런과 겹치기 | C를 안 고치면 뉴런당 2클럭 = 1,300클럭 (**1.09%**). C의 누산기를 고치면 3클럭 = 1,950클럭 (1.64%) | D에 뉴런 번호 레지스터 한 벌 추가, TB 타이밍 검사 전부 수정 (3클럭이면 C도 수정) | 중간 (제어가 겹쳐서 실수하기 쉬움) | 3클럭 버전만 필요 (C) | **비추천** (얻는 게 1%대) |
| P4 | TB 보강: 합성 이미지 16장, tb_edge, 검사기를 회귀에 포함. tb_npu_ctrl 타임아웃, tb_npu_top 클럭 수 검사 | R01~R03, R08 해소. 시뮬 5분 추가 | 작음 (이미 만들어 둠) | 낮음 | 제출물에 넣을지만 | **추천** |
| P5 | `o_done`을 IDLE에 들어갈 때 올리기 + `i_start` 상승 엣지 검출 | R05, R06 해소 (done = 1이면 항상 읽어도 됨) | D 몇 줄, FF 1~2개. 스펙 6-2 표와 tb_npu_ctrl 수정 | 낮음 | 스펙 문구 | 문서화는 필수, 코드 변경은 선택 |
| P6 | 스크립트 재현성 (3-6 목록) | 자동 판정, 다른 PC에서 그대로 실행 | 작음 | 낮음 | 불필요 | 추천 |
| P7 | 곱셈기 4개를 DSP로 (C) | LUT 약 −100, DSP 4개 사용 (1,248개 중). 타이밍 영향은 해 봐야 앎 | C 파일에 속성 한 줄 | 낮음 | 필요 (C) | 선택 ("DSP 0개" 질문 대비) |
| P8 | 어댑터 정리: RD_LAT = 2 경로 제거, `o_dout` 선택 레지스터에 enable, 외부 주소 범위 처리 | R09, R10, R14 해소. I/O 토글 조금 감소 | 작음 | 낮음 | B의 IP 확정 후 | 선택 |
| P9 | 주석 갱신: `npu_ctrl.v:16-18`의 "2 = 현재 조원2 IP" 등 예전 상태 설명 | 읽는 사람 혼란 방지 | 작음 | 없음 | 불필요 | 추천 |

### 3-2. P1 자세히: WMEM 4뱅크로 뉴런 4개 병렬

지금 구조: B의 WMEM은 뱅크 i에 "n % 4 == i인 뉴런"의 가중치를 넣어 둔 4뱅크야. 같은 주소를 주면 뉴런 4m, 4m+1, 4m+2, 4m+3의 같은 줄이 **동시에** 나와 (`memory_controller.v:84-121`, 주석도 "Bank i -> PE i"). 그런데 지금은 매 클럭 4뱅크를 다 읽고 어댑터의 MUX(`npu_mem_ctrl.v:162-164`)로 하나만 골라 쓰고 3개는 버려. BMEM도 한 줄에 bias 4개(128b)라 같은 모양이야. B의 README(`team_originals/B_memory_controller_1112/README.txt:50-51`)에는 "각 뱅크는 PE별 가중치를 병렬 출력"이라고 적혀 있어. 즉 B는 "PE i = 뉴런 4m+i"(뉴런 4개 병렬)를 생각하고 만들었고, C는 "PE 4개 = 한 뉴런의 입력 4개"로 만들어서 **B와 C의 해석이 서로 달라.** README #2(4뱅크냐 단일이냐)의 뿌리가 이거야. P1은 둘을 다 살리는 방법이기도 해 (뉴런 4개 × 입력 4개 = 곱셈기 16개).

바꾸면: C(곱셈 4개 + 누산기)를 4개 두고 뱅크 i의 출력을 C i에 바로 연결. 입력 x는 4개가 같이 씀.

| | 지금 | P1-a (A 1개, GO 4번 연속) | P1-b (A도 4개 동시) |
|---|---|---|---|
| 묶음(뉴런 4개)당 클럭 | 4 × (L + 3) | L + 2 + 4 = L + 6 | L + 3 |
| FC1 | 512 × 199 = 101,888 | 128 × 202 = 25,856 | 128 × 199 = 25,472 |
| FC2 | 128 × 131 = 16,768 | 32 × 134 = 4,288 | 32 × 131 = 4,192 |
| FC3 (뉴런 10개 = 묶음 4, 4, 2) | 10 × 35 = 350 | 38 + 38 + 36 = 112 | 3 × 35 = 105 |
| LAYER 2 + 끝 1 | 3 | 3 | 3 |
| **합계** | **119,009** | **30,259 (3.93배)** | **29,772 (4.00배)** |
| 고칠 파일 | - | D, top, 어댑터 | D, top, 어댑터 + A (또는 A 4개 + 묶는 회로) |

- P1-a가 가능한 이유: A는 `i_bias_we` 클럭에 bias를 잡고 `i_go` 클럭에 계산하는데, "GO j"와 "다음 뉴런의 bias_we"가 같은 클럭이어도 됨 (A가 GO 클럭에는 옛 bias를 쓰고 클럭 끝에 새 값으로 바뀜, `npu_postproc.v:41-44, 50`). 그래서 WAIT 2클럭 뒤에 GO를 4클럭 연속으로 낼 수 있고, A·C 파일은 한 줄도 안 고쳐도 됨. (클럭 수는 손으로 계산한 값이고 아직 구현·시뮬해 본 건 아님.)
- 자원 추정: C 3개 추가 = LUT +462, FF +291. acc 4:1 MUX +32 LUT, 지금의 w 뱅크 MUX −32 LUT. D는 비슷. → LUT 약 1,650 (칩의 1.4%), FF 약 580, BRAM 112 그대로.
- 타이밍: 지금 가장 느린 경로(BRAM 출력 → 뱅크 안 MUX → 4뱅크 MUX → 곱셈 → 곱 레지스터, 7.09 ns)에서 4뱅크 MUX가 빠져서 조금 나아짐. 대신 A 앞에 acc MUX가 1단 붙음 (지금 A 쪽 여유 4.77 ns).
- FC3 마지막 묶음은 뉴런이 2개뿐인데, 뱅크 2·3의 그 자리 64줄은 0이 들어 있음 (golden_check.py로 확인) → 남는 2개는 GO만 건너뛰면 됨.
- 위험과 비용: D의 루프가 "뉴런"에서 "묶음 + lane"으로 바뀌고 TB·검사기의 기대 순서도 바뀜. 이번에 만든 검사기, 합성 이미지, 버그 주입으로 다시 검증 가능. 보고서에서는 C 블록 설명이 "곱셈기 4개"에서 "16개"로 바뀌니 조원3과 합의 필요. 참고로 스펙 v0.2 2절(4쪽)에도 "PE 16개로 늘려도 BRAM은 거의 그대로이고 늘어나는 건 곱셈기(4개 → 16개)뿐"이라고 적혀 있어서 같은 방향이야. 지금 4뱅크는 이미 BRAM 112개로 구현돼 있어서 추가 BRAM은 없음.

### 3-3. P2 자세히: ena 게이팅

- 지금: WMEM 4뱅크와 BMEM의 `ena`가 1 고정. 다만 뱅크 안에서는 IP가 주소 윗비트로 "그 주소가 들어 있는 primitive"만 켜고 있어 (뱅크당 28개 중 약 8개: 4096×9짜리 3개 + 32768×1짜리 5개. `reports/review/ram_utilization.rpt`). 그래서 매 클럭 4뱅크 × 약 8개 = 32개가 읽기 동작을 해. 필요한 건 한 뱅크의 8개.
- 가정 계산: 배선된 설계에서 WMEM enable 선 107개의 "켜져 있는 비율"만 자기 뱅크 차례(전체 클럭의 24.6%)로 줄여서 전력을 다시 계산 (RTL은 안 고침. `scripts/review/power_whatif.tcl`).

| | 합계 | 동적 | BRAM | WMEM 뱅크 0 / 1 / 2 / 3 |
|---|---|---|---|---|
| 지금 (스위칭 기록) | 0.360 W | 0.071 | 0.040 | 0.011 / 0.010 / 0.010 / 0.009 |
| WMEM enable 게이팅 가정 | 0.352 W | 0.063 | 0.032 | 0.010 / 0.007 / 0.007 / 0.007 |

- 뱅크 0에는 enable이 1에 묶인 primitive 5개가 있어서 이 계산으로는 못 줄였어 (다른 뱅크처럼 0.007 W가 된다고 보면 −0.003 W 추가). BMEM(0.003 W)도 같은 이유로 그대로. 다 합쳐도 **약 −0.012 W**가 상한.
- 왜 작은가: 뱅크당 약 0.007 W는 enable을 줄여도 남아. BRAM은 클럭이 들어가는 것만으로 쓰는 전력이 커.
- 조심할 점: 스위칭 기록과 넷 이름이 맞은 비율이 1,973 / 3,356 (59%)이라 숫자는 "대략"으로 볼 것.
- P1을 하면 매 ISSUE 클럭에 4뱅크를 다 쓰게 되므로 뱅크별 게이팅은 의미가 없어지고, "ISSUE가 아닐 때 끄기"만 남음 (연산 중에는 클럭의 1.6%, 연산을 안 할 때는 100%).

### 3-4. P3 자세히: 뉴런당 3클럭 오버헤드 겹치기

- 지금 뉴런 하나 = ISSUE L + WAIT 2 + GO 1. 오버헤드 3 × 650 = 1,950클럭 = 전체의 1.64%.
- C를 안 고치고 줄일 수 있는 건 2클럭: C는 `acc_clr`가 누산보다 우선이라(`npu_pe_array.v:54-55`) 다음 뉴런의 첫 곱이 "GO 다음 클럭"부터 누산기에 들어가야 해. 그 조건만 지키면 다음 뉴런의 첫 ISSUE를 지금보다 2클럭 앞(앞 뉴런의 WAIT 둘째 클럭 자리)에 둘 수 있고, 그러면 앞 뉴런의 GO와 다음 뉴런의 ISSUE k1이 같은 클럭이 돼.
- 3클럭을 다 없애려면 C의 누산기가 "지우면서 동시에 첫 곱을 싣기"를 해야 함 (C 수정).
- 효과: 119,009 → 117,709 (1.09%) 또는 117,059 (1.64%). P1과 같이 하면 묶음이 163개뿐이라 326~489클럭.
- D 안에서 "주소를 내는 뉴런"과 "GO를 내는 뉴런"이 동시에 달라지므로 n, lane, oaddr, bias 주소를 두 벌로 들고 있어야 하고, 레이어 전환과 뱅크 포인터 되돌림 시점도 다시 맞춰야 해. 얻는 것에 비해 위험이 커서 비추천.

### 3-5. 타이밍 여유

- 구현 결과: WNS +2.553 ns → 지금 배치에서 최소 주기 약 7.45 ns = **약 134 MHz**. 10 ns 제약에서 도구가 "충족"하고 멈춘 결과라 실제 한계는 더 높을 수 있음 (제약을 조여서 다시 구현해 보지는 않았어).
- 블록별 가장 느린 경로 (끝점 기준): C +2.553 ns (BRAM → 곱셈, 10단), B +3.453 ns (D 뱅크 포인터 → WMEM enable), A +4.766 ns (bias → 덧셈 → ReLU → shift → 포화 → 묶기, 15단), D +6.112 ns.
- hold: 최소 +0.054 ns (D bias 포인터 → BMEM 주소). 배선 도구가 맞춰 놓은 값이라 양수면 충분.
- 가이드의 XDC가 10 ns 고정이라 주파수를 올릴 일은 없고, 2.55 ns 여유는 P1을 해도 충분해 보여.

### 3-6. P6 자세히: 스크립트 재현성

- `run_sim.tcl:158-160`: TB가 FAIL이어도 `exit 0`. result.txt를 사람이 읽어야 함 → PASS 문자열이 없으면 `exit 1`.
- `run_sim.tcl:23-27`: 인자가 자리로 고정 (`100 fresh oreg_on`). `fresh`만 쓰려 해도 장수를 먼저 써야 함.
- `run_sim.tcl:106-110`: TB의 `HEX_DIR` 줄을 문자열 치환으로 바꿈 → TB의 그 줄을 조금만 고쳐도 조용히 치환이 안 됨. 시뮬 실행 폴더에 hex/를 복사하는 방식(`scripts/review/xrun.sh`)이 더 단순.
- 저장소 루트에 `*.log`, `*.jou`, `*.backup.*`가 계속 쌓임 (git에서는 제외돼 있음) → `-log logs/... -journal logs/...`.
- Vivado 프로젝트를 여는 방식이라 느리고 프로젝트가 잠김. `xrun.sh`는 프로젝트 없이 100장 + 검사기가 2분 32초.
- `run_sim.bat` 더블클릭 실행은 아직 아무도 확인 안 함 (CLAUDE.md에도 적혀 있음).
- 합성·구현 스크립트(`run_impl.tcl`)는 문제 못 찾음. 두 런 모두 지금 RTL과 일치 (`needs_refresh = 0`).

---

## 4. 조원4가 다음에 결정할 것

1. **P1(뉴런 4개 병렬)을 할지.** 먼저 가이드 40쪽 이후에 평가 기준(속도, 면적, 전력 점수)이 있는지 확인. 한다면 11/17 통합 회의에서 조원3(C 설명 범위)·조원2(4뱅크를 만든 의도)과 합의. A·B·C 파일은 안 고쳐도 돼.
2. **R05 (`o_done`이 1클럭 먼저)**: 문서에 "`o_busy == 0 && o_done == 1`을 기다릴 것"만 적을지, D 코드를 바꿀지 (P5).
3. **R01~R03, R08 (테스트 구멍)**: 합성 이미지 16장 + `tb_edge` + 검사기를 정식 회귀로 쓸지, 제출 zip에 `tb/review/`를 넣을지. 기존 TB 2개에 타임아웃과 클럭 수 검사를 넣을지.
4. **R04 (가중치를 COE로만 넣는 것)**: 11/17 회의에서 교수님께 물어볼 항목으로 올릴지. 감점 위험이 가장 큰 미결 사항이야.
5. **R07**: README의 "critical warning 0개" 문구 수정, 핀 제약을 넣을지 (보드에 올릴 계획이 있으면).
6. **R17**: MNIST를 받아서(공개 데이터 4개 파일, 약 11 MB) 입력 hex와 1만 장 정확도 99.30%까지 독립 확인할지. 파이썬 모델로는 몇 초, RTL로 1만 장을 돌리면 약 3시간 (100장에 약 1분 45초 기준).
7. **팀원에게 전달**: 조원1(A)에게 R01 포화 테스트 벡터, 조원2(B)에게 R18·R19·P2·R04, 조원3(C)에게 R13 timescale·P7 DSP·P1.
8. **README / CLAUDE.md 갱신**: 이번 리뷰 산출물 위치(`tb/review/`, `scripts/review/`, `reports/review/`, 이 문서)와 R07 문구. 기존 문서는 안 건드렸어. 고쳐도 되면 말해 줘.
9. **P2, P3**: 내 판단은 P2는 B에게 제안만, P3는 안 함. 다르게 하고 싶으면 알려 줘.

---

## 5. 다시 돌리는 방법

전부 저장소 루트에서 Git Bash. Vivado 프로젝트(`vivado_sim/`)가 있어야 함 (`run_sim.tcl`을 한 번 돌린 상태). 시뮬레이션은 Vivado를 띄우지 않고 xvlog → xelab → xsim만 씀.

```bash
python scripts/review/golden_check.py          # 골든 독립 확인 (numpy만 필요, 약 20초)
python scripts/review/gen_stress.py            # 합성 이미지 16장 + 정답 (build/review/stress_hex)
```
```bash
bash scripts/review/xrun.sh base_ctrl rtl "TB_RD_LAT=1" "tb/tb_npu_ctrl.v" "tb_npu_ctrl"
```
```bash
bash scripts/review/xrun.sh top100_chk rtl "N_IMG=100 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
```
```bash
bash scripts/review/xrun.sh edge rtl "CHK_TOP=tb_edge.u_top CHK_IMG=tb_edge.cur_img CHK_STAGES" "tb/review/npu_checker.v tb/review/tb_edge.v" "tb_edge npu_checker"
```
```bash
HEX_SRC="$PWD/build/review/stress_hex" STAGE_SRC="$PWD/build/review/stress_hex" bash scripts/review/xrun.sh stress rtl "N_IMG=16 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
```
```bash
bash scripts/review/run_mutants.sh             # 버그 주입 49종 (약 1시간)
```
```bash
bash scripts/review/xrun_netlist.sh net_synth synth_funcsim 2      # 넷리스트 시뮬 (netlist_export.tcl 먼저)
```

- 결과는 `build/review/<run 이름>/xsim.log` (git 제외 폴더). 요약은 `reports/review/`.
- 주의: `xrun.sh`가 도는 동안 그 스크립트 파일을 고치면 안 됨 (bash가 파일을 읽으면서 실행함. 이번에 한 번 겪음).
- iverilog는 이 PC에 없어서 안 씀. 행동 모델(`sim_models/`)로도 xsim에서 2장 PASS 확인 (RD_LAT 1, 2 둘 다).

## 6. 확인 못 한 것

- **가이드 40~62쪽**: 파일이 39쪽까지만 있어. 평가 기준이나 추가 규칙이 뒤에 있을 수 있음.
- **MNIST 원본 → 입력 hex, 1만 장 정확도 99.30%**: 이 PC에 데이터가 없어서 못 함 (R17). 확인한 건 "받은 입력 hex 100장 이후"와 합성 이미지 16장.
- **B 원본 IP(.xci, 2024.1, 출력 레지스터 ON)**: 그 IP 자체는 안 돌림. 내 스크립트가 2024.2에서 같은 설정(출력 레지스터만 OFF)으로 다시 만든 IP로만 확인. 설정 대조는 2-3 표.
- **A·B·C 내부**: 각 블록의 단위 TB(tb_postproc 등)는 다시 안 돌림. A·C는 통합 상태에서의 동작과 복사본 버그 주입(11종)만 봄. B의 `memory_controller.v`는 읽기만 함.
- **넷리스트 시뮬 장수**: 합성 후 2장, 배선 후(지연 없음) 1장만 (장당 5분 이상 걸려서). 100장을 넷리스트로 돌리지는 않았어.
- **배선 후 타이밍 시뮬(SDF)**: FAIL 상태로 미해결, 과제 범위 밖 (2-8). 시뮬레이터 문제로 추정하지만 통과하는 타이밍 시뮬로 확인하지는 못했어.
- **보드 동작, 핀 배치, I/O 지연 제약, 리셋 동기화**: 범위 밖 (R07, R15).
- **Fmax 실측**: WNS로 계산한 추정만. 제약을 조여서 다시 구현해 보지 않음.
- **전력**: 스위칭 기록은 사진 1장, 넷 매칭 59%. ena 게이팅은 RTL을 고쳐 본 게 아니라 스위칭 확률을 덮어쓴 가정 계산.
- **P1의 클럭 수와 자원**: 손 계산과 지금 블록 크기로 한 추정. 구현해 보지 않았어.
- **형식 검증(formal)**: 안 함. 버그 주입 49종도 전부가 아니라 표본이야.
- **iverilog**: 이 PC에 없어서 xsim으로 대신함. `run_sim.bat` 더블클릭도 안 해 봄.
