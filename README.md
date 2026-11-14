# D 블록 (npu_ctrl + npu_top) + A·B·C·D 통합 · 2026-11-14 · 조원4

## 결과 요약 (Vivado 2024.2, 실제 Block Memory Generator IP, xck26-sfvc784-2LV-c)
| 단계 | 결과 | 핵심 숫자 | 근거 파일 |
|---|---|---|---|
| D 단위 `tb_npu_ctrl` (RD_LAT=1) | **PASS** | GO 512/128/10 · bias_we 650 · 마지막 o_waddr 117,055 · **119,009클럭** | `reports/sim_100img.txt` |
| 통합 `tb_npu_top` 10장 | **PASS** | FC1 128/128, FC2 32/32, FC3 10/10 전부 golden v2와 비트 일치 | 〃 (앞 10장) |
| 통합 `tb_npu_top` 100장 | **PASS** | **100/100장 비트 일치, 예측 100/100**, 장당 119,659클럭(약 1.2 ms), 시뮬레이터 경고 0개 | 〃 |
| 합성 (`npu_top`, 10 ns 클럭) | 완료 | LUT 1,398 · FF 341 · RAMB36 106 + RAMB18 13 · DSP 0 | `reports/synth_*.rpt` |
| 구현 (place & route) | **100 MHz 타이밍 충족** | **WNS +2.138 ns · WHS +0.041 ns** (실패 경로 0 / 2,334) | `reports/impl_*.rpt` |

구현 후 자원 사용량 (K26 전체 대비)

| 자원 | 사용 | 전체 | 비율 | 블록별 |
|---|---|---|---|---|
| CLB LUT | 1,199 | 117,120 | 1.0% | B 778 (memory_controller + BRAM IP 내부 746, 어댑터 32) · D 211 · C 154 · A 57 |
| FF | 341 | 234,240 | 0.15% | A 97 · C 97 · B 85 · D 62 |
| BRAM 타일 | **112** | 144 | **77.8%** | RAMB36 106 + RAMB18 12. WMEM 뱅크당 RAMB36 26 + RAMB18 2, BMEM RAMB36 2, IMEM_A·ACT_A·ACT_B·OMEM 각 RAMB18 1 |
| DSP | 0 | 1,248 | 0% | C의 8×8 곱셈 4개가 LUT로 구현됨 |
| 핀 (IOB) | 82 | 189 | 43% | 핀 배치 제약 없음 (자동 배치) |

- 가장 느린 경로: `u_D/r_wb_ptr[13]` → WMEM 뱅크0 BRAM의 enable 핀 (주소 상위 비트로 BRAM 26개 중 하나를 고르는 디코드). 지연 7.22 ns 중 97%가 배선.
- 아직 안 한 것: 핀 배치(PACKAGE_PIN), I/O 지연 제약, 구현 후(post-route) 시뮬레이션, 보드 동작. 타이밍 리포트는 칩 내부 레지스터 사이 경로만 검사한 결과야 (입력 47개, 출력 34개 포트는 I/O 지연 제약 없음).
- iverilog + BRAM 행동 모델(`sim_models/`)로 11/14에 미리 돌린 결과(100장 일치)와 Vivado 결과가 같아. 단, 그 뒤에 고친 `npu_ctrl.v`(아래 2절 마지막 줄)는 Vivado에서만 회귀를 돌렸어.

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
  tb_npu_ctrl.v     D 단위 TB
  tb_npu_top.v      통합 TB (이미지 N장)
constr/
  npu_top.xdc       10 ns 클럭 제약 (핀 배치 없음)
coe/                BRAM 초기값 (조원2 zip의 weight_bank0~3.coe, bias_128bit.coe 그대로)
hex/                통합 TB용 golden v2 (handoff_D_1112/golden과 같은 파일) + iverilog용 뱅크 초기값
run_sim.tcl / run_sim.bat   Vivado batch 시뮬레이션 (프로젝트 vivado_sim/ 생성, IP 10개 생성, 두 TB 실행)
run_impl.tcl                Vivado batch 합성 + 구현 + 리포트
reports/            시뮬 결과(sim_100img.txt), 합성·구현 사용량/타이밍 리포트, impl_summary.txt
sim_models/
  bram_models.v     iverilog 전용 BRAM 모델. Vivado에는 넣지 말 것!
wave_fc2_n27_n28.png  통합 파형 (FC2 뉴런 27 → 28 경계, iverilog)
```

## 2. 설계 핵심
- FSM 상태 6개 (스펙 6-2): IDLE → ISSUE(L클럭) → WAIT(RD_LAT+1클럭) → GO → … → LAYER / DONE
- 레이어 설정표: golden v2 기준 shift FC1 **11**, FC2 **7** (스펙 v0.2 표는 아직 10/9)
- 메모리 흐름 (handoff 11/12 기준): FC1 IMEM_A → ACT_A, FC2 ACT_A → ACT_B, FC3 ACT_B → OMEM
- `RD_LAT` parameter: 스펙은 1, 현재 B IP는 WMEM/BMEM 출력 레지스터가 ON이라 top에서 2로 사용
- WMEM 주소를 두 가지로 냄: `o_waddr`(스펙의 단일 WMEM 기준), `o_wbank_addr`+`o_wbank_sel`(B의 4뱅크 구조 기준).
  곱셈·나눗셈 없이 포인터 +1, 뉴런의 마지막 줄에서 lane ≠ 3이면 묶음 시작으로 되돌림
- (11/14 수정) 되돌리는 시점을 GO에서 ISSUE 마지막 클럭으로 옮김. B의 WMEM은 ena가 1로 고정이라 ISSUE가 아닌 클럭의 주소도 실제로 읽히는데, 예전 방식은 FC3 마지막 묶음에서 포인터가 29,280(범위 밖)에 4클럭 머물러서 IP 모델이 `Address 7260 is outside range` 경고를 사진당 32번 냈어. 그 데이터는 안 쓰여서 결과는 같았고, 지금은 주소가 항상 0~29,279 안에 있어 (TB가 매 클럭 검사).

## 3. 다시 돌리는 방법 (Vivado 2024.2)
1. **시뮬레이션**: `run_sim.bat` 더블클릭. 또는
   ```
   vivado -mode batch -source run_sim.tcl -log run_sim.log -notrace                (10장)
   vivado -mode batch -source run_sim.tcl -log run_sim.log -notrace -tclargs 100   (100장)
   ```
   새 프로젝트 `vivado_sim/`를 만들고(이미 있으면 재사용), 조원2 .xci와 같은 설정으로 BRAM IP 10개를 2024.2에서 새로 만든 다음 `tb_npu_ctrl` → `tb_npu_top`을 돌려. 결과는 `result.txt`, 로그는 `logs/`. 기존 `aissd_mnist_npu` 프로젝트는 건드리지 않아. 10장은 1~2분, 100장도 몇 분이면 끝나.
2. **합성 + 구현**: 시뮬을 한 번 돌린 뒤
   ```
   vivado -mode batch -source run_impl.tcl -log run_impl.log -notrace
   ```
   결과는 `result_impl.txt`, 리포트는 `reports/`. IP가 이미 합성돼 있으면 약 10분, 처음이면 IP 10개 합성 때문에 더 걸려.
   **주의**: 병렬 작업 수(`JOBS`)는 2로 둘 것. 8로 돌렸더니 RAM 16GB PC에서 메모리가 바닥나 IP 합성 런 3개가 에러 메시지 없이 죽었어.
3. **GUI로 직접 넣을 때**: Design Sources에 `rtl/` 6개, IP는 조원2 zip의 `ip/*.xci` 10개(각 IP의 COE 경로를 내 PC 경로로 지정 후 Generate Output Products. 2024.1에서 만든 IP라 2024.2에서 잠겨 보이면 Upgrade IP), Simulation Sources에 `tb/` 2개. `sim_models/bram_models.v`는 **넣지 않음**(IP와 이름이 겹침). `tb_npu_top.v` 맨 위 `HEX_DIR`을 내 PC의 `hex/` 절대경로로 변경(슬래시 `/`, 끝에 `/`). 합성할 때는 `constr/npu_top.xdc` 추가, top = `npu_top`.
4. 파형 캡처할 신호 추천: `u_D/r_state, r_n, r_k, valid, acc, bias_we, bias, go, lane, we, wdata, oaddr`

iverilog (참고):
```
iverilog -g2005 -DN_IMG=10 -o top.vvp sim_models/bram_models.v rtl/*.v tb/tb_npu_top.v && vvp top.vvp
iverilog -g2005 -DTB_RD_LAT=1 -o ctrl.vvp rtl/npu_ctrl.v tb/tb_npu_ctrl.v && vvp ctrl.vvp
```

## 4. 팀 확인 필요 (불일치 목록, 11/14 갱신)
| # | 블록 | 내용 | 지금 처리 | 결정 필요 |
|---|---|---|---|---|
| 1 | B | WMEM·BMEM 출력 레지스터 ON → 읽기 지연 2 (스펙은 OFF, 지연 1) | 어댑터에서 x도 1클럭 늦추고 D를 RD_LAT=2로. **이 구성으로 100장 일치 + 100MHz 충족(WNS 2.14 ns) 확인** | ON 유지로 확정할지. 유지하면 뉴런당 +1클럭(총 119,659). OFF(RD_LAT=1)는 합성·타이밍을 안 돌려봤음 |
| 2 | B | WMEM이 4뱅크(뱅크 i = n%4 뉴런) 구조. 스펙과 11/10 카톡은 단일 32b × 117,056 | D가 4뱅크 주소도 같이 냄 (`o_wbank_addr`, `o_wbank_sel`). 4뱅크로 100장 일치 확인 | 4뱅크를 최종으로 할지. BRAM은 4뱅크 합계 RAMB36 104 + RAMB18 8 |
| 3 | B | 모듈 이름 memory_controller, 포트 clk/rst(active-high 동기) | 어댑터에서 변환 | 이름 규칙에 맞출지 |
| 4 | B | npu_mem_ctrl(외부 인터페이스, busy MUX, 읽기 MUX) 없음, WMEM·BMEM 외부 쓰기 불가(COE만) | 어댑터가 대신 함. 임시 주소 맵 `i_addr[19:17]`: 2 IMEM_A, 3 ACT_A, 4 ACT_B, 5 OMEM | 정식 npu_mem_ctrl을 누가 마무리할지, 주소 맵 확정, 가중치를 COE로만 넣어도 되는지 |
| 5 | 스펙 | v0.2 메모리 맵(ACT_A 228줄 등), shift 10/9가 옛날 값 | handoff 11/12 + golden v2 기준으로 구현 | 스펙 v1.0 갱신 |
| 6 | C | C_pe_array_final.zip은 clk/rstn, handoff_D/rtl은 i_clk/i_rstn | handoff 버전 사용 | 최종본 하나로 정리 |
| 7 | D | 이름 표에 없는 포트 추가: `o_rd_en`, `o_wbank_addr`, `o_wbank_sel` | — | 이름 규칙 표에 추가 |
| 8 | B | (해결) 합성·BRAM 사용량·타이밍 미확인 | 통합 상태로 합성·구현 완료: BRAM 112/144 타일, 100MHz 충족 | B README의 "Vivado 강제 종료"가 메모리 부족이었는지 확인 (나도 병렬 8개로 돌렸을 때 IP 런이 죽었고 2개로 낮추니 해결) |
| 9 | B | IMEM_B(더블 버퍼용)를 아무도 안 씀 | 어댑터에서 req=0으로 묶음. 구현 단계에서 자동으로 지워짐 (RAMB18 13 → 12) | 더블 버퍼를 쓸지, 안 쓰면 IP를 뺄지 |
| 10 | B | WMEM·BMEM의 ena가 1로 고정 → ISSUE가 아닌 클럭에도 읽기가 일어남 | D가 주소를 항상 범위 안에 두도록 수정 (2절 마지막 줄) | ena를 req에 연결할지 (전력 절약). 지금도 동작은 맞음 |
| 11 | C | 곱셈 4개가 DSP가 아니라 LUT로 합성됨 (DSP 0개) | 그대로 둠. 타이밍 문제 없음 | 의도한 건지. 발표에서 "DSP 몇 개" 질문이 나오면 답할 숫자 |
| 12 | 공통 | IP가 2024.1에서 만들어짐, 내 PC는 2024.2 | 같은 설정으로 2024.2에서 새로 생성 (`run_sim.tcl`) | 팀 Vivado 버전, 최종 제출 프로젝트를 누구 PC에서 만들지 |
| 13 | 공통 | 핀 배치·I/O 지연 제약 없음 | 클럭 제약만 넣음 (`constr/npu_top.xdc`) | 보드에 올릴 건지, 시뮬 + 합성 리포트까지인지 |
