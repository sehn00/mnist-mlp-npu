# D 블록 (npu_ctrl + npu_top) + 통합 리허설 · 2026-11-14 · 조원4

## 결과 요약 (iverilog, 조원2 IP 설정을 흉내 낸 BRAM 모델 사용)
| 테스트 | 결과 |
|---|---|
| `tb_npu_ctrl` (RD_LAT=1, 스펙) | PASS · GO 512/128/10 · bias_we 650 · 마지막 o_waddr 117,055 · **119,009클럭** |
| `tb_npu_ctrl` (RD_LAT=2, 현재 B) | PASS · 119,659클럭 |
| `tb_npu_top` A+B+C+D 통합 | **이미지 100장 전부 FC1·FC2·FC3 golden v2와 비트 단위 일치, 예측 100/100** |
| 일부러 shift를 10으로 틀리게 한 경우 | FAIL로 잡힘 (TB가 제대로 검사하는지 확인) |

Vivado 실제 IP로는 아직 안 돌려봤어. 아래 3절 순서대로 돌려서 확인해야 해.

## 1. 폴더 구성
```
rtl/
  npu_ctrl.v        D 제어기 (새로 작성)
  npu_top.v         최상위 (새로 작성)
  npu_mem_ctrl.v    B 임시 어댑터 (새로 작성, memory_controller.v를 수정 없이 감쌈)
  npu_postproc.v    A (조원1 blockA_share 그대로)
  npu_pe_array.v    C (handoff_D_1112/rtl 버전 그대로: i_clk/i_rstn 이름)
  memory_controller.v  B (조원2 memory_controller.zip 그대로)
tb/
  tb_npu_ctrl.v     D 단위 TB
  tb_npu_top.v      통합 TB (이미지 N장)
sim_models/
  bram_models.v     iverilog 전용 BRAM 모델. Vivado에는 넣지 말 것!
hex/                통합 TB용 golden v2 (handoff_D_1112/golden과 같은 파일) + iverilog용 뱅크 초기값
wave_fc2_n27_n28.png  통합 파형 (FC2 뉴런 27 → 28 경계)
```

## 2. 설계 핵심
- FSM 상태 6개 (스펙 6-2): IDLE → ISSUE(L클럭) → WAIT(RD_LAT+1클럭) → GO → … → LAYER / DONE
- 레이어 설정표: golden v2 기준 shift FC1 **11**, FC2 **7** (스펙 v0.2 표는 아직 10/9)
- 메모리 흐름 (handoff 11/12 기준): FC1 IMEM_A → ACT_A, FC2 ACT_A → ACT_B, FC3 ACT_B → OMEM
- `RD_LAT` parameter: 스펙은 1, 현재 B IP는 WMEM/BMEM 출력 레지스터가 ON이라 top에서 2로 사용
- WMEM 주소를 두 가지로 냄: `o_waddr`(스펙의 단일 WMEM 기준), `o_wbank_addr`+`o_wbank_sel`(B의 4뱅크 구조 기준).
  곱셈·나눗셈 없이 포인터 +1, 뉴런이 끝날 때 lane ≠ 3이면 L만큼 되돌림

## 3-0. 제일 쉬운 방법: run_sim.bat 더블클릭
새 프로젝트(`vivado_sim/`)를 만들고, 조원2 .xci와 같은 설정으로 BRAM IP 10개를 새로 만든 다음(2024.2 버전 차이 회피), `tb_npu_ctrl` → `tb_npu_top`(10장)을 자동으로 돌려. 결과는 `result.txt`, 로그는 `logs/`에 남아. 기존 `aissd_mnist_npu` 프로젝트는 건드리지 않아.

## 3. Vivado에서 직접 넣어서 돌리는 순서 (Vivado 2024.1, 프로젝트 aissd_mnist_npu)
1. **Design Sources**: `rtl/` 파일 6개 전부
2. **IP**: memory_controller.zip의 `ip/*.xci` 10개 추가 → 각 IP를 더블클릭해서 COE 경로를 내 PC 경로로 지정
   (WMEM: `weight_bank0~3.coe`, BMEM: `bias_128bit.coe`, 조원2 zip의 hex 폴더) → Generate Output Products
3. **Simulation Sources**: `tb/tb_npu_ctrl.v`, `tb/tb_npu_top.v`
   - `sim_models/bram_models.v`는 **넣지 않음** (실제 IP와 이름이 겹침)
4. `tb_npu_top.v` 맨 위의 HEX_DIR을 내 PC의 `hex/` 절대경로로 바꾸기 (슬래시 `/` 사용, 끝에 `/`)
   ```verilog
   `define HEX_DIR "C:/aissd/aissd_D/hex/"
   ```
5. 단위 테스트: `tb_npu_ctrl`을 Set as Top → Run Behavioral Simulation → Tcl 콘솔에 `run all`
   → `*** tb_npu_ctrl PASS ***`, 119,009 clocks
6. 통합 테스트: `tb_npu_top`을 Set as Top → `run all` (10장 약 12 ms 시뮬레이션 시간)
   → 이미지마다 `FC1 128/128 FC2 32/32 FC3 10/10 match … PASS`, 마지막에 `*** tb_npu_top PASS ***`
7. 파형 캡처할 신호 추천: `u_D/r_state, r_n, r_k, valid, acc, bias_we, bias, go, lane, we, wdata, oaddr`

iverilog로 다시 돌리기 (참고):
```
iverilog -g2005 -DN_IMG=10 -o top.vvp sim_models/bram_models.v rtl/*.v tb/tb_npu_top.v && vvp top.vvp
iverilog -g2005 -DTB_RD_LAT=1 -o ctrl.vvp rtl/npu_ctrl.v tb/tb_npu_ctrl.v && vvp ctrl.vvp
```

## 4. 팀 확인 필요 (불일치 목록)
| # | 블록 | 내용 | 지금 처리 | 결정 필요 |
|---|---|---|---|---|
| 1 | B | WMEM·BMEM 출력 레지스터 ON → 읽기 지연 2 (스펙은 OFF, 지연 1) | 어댑터에서 x도 1클럭 늦추고 D를 RD_LAT=2로 | 끌지 유지할지. 유지하면 BRAM 115개 읽기 MUX 타이밍엔 유리, 뉴런당 +1클럭 (총 119,659) |
| 2 | B | WMEM이 4뱅크(뱅크 i = n%4 뉴런) 구조, 스펙은 단일 32b × 117,056 | D가 4뱅크 주소도 같이 냄 | 이대로 갈지 단일 WMEM으로 바꿀지 |
| 3 | B | 모듈 이름 memory_controller, 포트 clk/rst(active-high 동기) | 어댑터에서 변환 | 이름 규칙에 맞출지 |
| 4 | B | npu_mem_ctrl(외부 인터페이스, busy MUX, 읽기 MUX) 없음, WMEM·BMEM 외부 쓰기 불가(COE만) | 어댑터가 대신 함. 임시 주소 맵: 2 IMEM_A, 3 ACT_A, 4 ACT_B, 5 OMEM | 정식 npu_mem_ctrl을 누가 마무리할지 |
| 5 | 스펙 | v0.2 메모리 맵(ACT_A 228줄 등), shift 10/9가 옛날 값 | handoff 11/12 + golden v2 기준으로 구현 | 스펙 v1.0 갱신 |
| 6 | C | C_pe_array_final.zip은 clk/rstn, handoff_D/rtl은 i_clk/i_rstn | handoff 버전 사용 | 최종본 하나로 정리 |
| 7 | D | 이름 표에 없는 포트 추가: o_rd_en, o_wbank_addr, o_wbank_sel | — | 이름 규칙 표에 추가 |
| 8 | B | 합성·BRAM 사용량·타이밍 미확인 (README: Vivado 강제 종료) | — | 통합 후 합성으로 확인 |
