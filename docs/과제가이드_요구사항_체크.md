# 과제 가이드(AISSD_project, 39쪽) 요구사항 체크 · 2026-11-14 (저녁에 출력 레지스터 OFF 재검증 결과로 상태 갱신)

근거: docs/AISSD_project_과제설명및요구사항.pdf (슬라이드 번호는 62쪽 중 1-39쪽만 있음 → 40쪽 이후 파일이 따로 있을 수 있음)

## 1. 설계 규칙 (위반하면 감점 위험)
| 규칙 (쪽) | 현재 상태 | 조치 |
|---|---|---|
| BMEM 생성 시 **Primitives Output Register disabled** (p.9) | ✅ 내 쪽(D·어댑터·top, `run_sim.tcl`이 만드는 IP 10개)은 OFF, RD_LAT=1. Vivado 100장 일치(장당 119,009클럭) + 100MHz 충족 확인 (11/14). ⚠️ B의 11/12 .xci 원본은 아직 WMEM·BMEM ON | **조원2가 wmem_bank0~3, bmem_128을 OFF로 재생성 필요**. `memory_controller.v`의 weight_valid/bias_valid 지연도 2클럭 → 1클럭으로 (수정 제안) |
| SRAM은 BMEM으로, reg로 SRAM 구현 금지 (p.5) | ✅ | - |
| initial, delay, readmemh/readmemb는 테스트벤치(tester)와 주어진 SRAM 파일에서만 (p.4-5) | ✅ rtl/ 에는 없음. sim_models/bram_models.v(iverilog 전용)는 제출물에서 빼야 함 | 제출 zip에서 sim_models 제외 |
| 타이밍 slack 양수 (WNS, WHS 둘 다) (p.5, p.37) | ✅ OFF 구성 기준 WNS +2.553 ns, WHS +0.054 ns (실패 경로 0 / 2,165). 이전 ON 구성은 +2.138 / +0.041 | 팀 최종 프로젝트(B가 재생성한 IP)로 한 번 더 확인 |
| XDC: `create_clock -name i_clk -period 10 [get_ports i_clk]` (p.33) | ✅ constr/npu_top.xdc를 가이드와 같은 한 줄로 바꿈 (클럭 이름 i_clk) | - |
| 사용자와 통신하는 입출력 인터페이스(예: SRAM 인터페이스) (p.2), ~CEN = ena, ~WEN = wea (p.12) | ✅ top i_cen/i_wen active-low | - |
| 제출: 모든 .v + 테스트벤치 + **데이터 넣는 hex 파일** (p.3) | ⚠️ WMEM·BMEM은 COE 초기화 전용(B가 wea=0 고정). 테스트벤치가 hex로 가중치를 넣는 구조가 아님 | 팀/교수님 확인: COE 초기화로 괜찮은지, 외부 포트 쓰기가 필요한지 (필요하면 B 수정) |

## 2. 보고서 필수 항목 (p.13) → 필요한 캡처
| # | 항목 | 필요한 것 | D(조원4) 몫 |
|---|---|---|---|
| 1 | 블록도 (전체 + **학생별 IP 상세, 따로 제출**) | 전체 블록도, D 내부 블록도 | D 상세 블록도 |
| 2 | 하드웨어 매핑, 메모리 트랜잭션 | 루프/타일링, 메모리 흐름 | - |
| 3 | 검증 방법과 화면 캡처 | 골든 비교 방식, TB 결과 콘솔 | 통합 TB 결과 |
| 4 | 파형 **4장**: SRAM 읽기, SRAM 쓰기, 연산 시작, 연산 끝 (p.19-20) | Vivado 파형 캡처 | 통합 TB에서 캡처 |
| 5 | 레이어별 정답 비교 | FC1/FC2/FC3 골든 일치 표 | 통합 TB 결과 |
| 6 | MNIST **테스트셋** 하드웨어 정확도 | 몇 장으로 할지 교수님 확인 (1만 장 시뮬은 시간 큼) | - |
| 7 | 구현 후 schematic: 전체 + 확대, **IP별** 전체 + 확대 (p.22-24) | Vivado schematic 캡처 | D 블록 schematic |
| 8 | 구현 결과: Device 화면, 자원 사용량, 타이밍, **전력(breakdown)** (p.28-39) | reports + 캡처. 숫자는 `reports/impl_utilization.rpt`, `impl_timing_summary.rpt`, `impl_power.rpt`에 있음 (합계 0.367 W = 동적 0.077 + 정적 0.289). GUI 캡처(Device, Power 화면)는 아직 안 함 | - |
| 9 | 자체 평가, 결론 | - | - |
| 10 | 팀원별 역할 | - | D + 통합 |

## 3. 제출 (p.3)
- 팀당 1개. zip 이름 `{학번}_{한글이름}.zip`, 보고서 `.docx` + `.pdf` (템플릿 변경 금지, 템플릿 파일은 이 폴더에 없음 → e-class에서 받기)
- 마감: 최종 발표 하루 전, 늦으면 0점
