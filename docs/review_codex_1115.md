# Verilog NPU 외부 검수 · 2026-11-15

## 요약

**전체 판정 — 현재 생성된 RD_LAT=1 구성의 코어는 정적 검수와 독립 수치 대조에서 통과했습니다. 최종 통합·제출은 조건부 통과입니다.** 제출 IP와 RTL의 읽기 지연을 함께 고정하고, 외부 주소 맵과 완료 신호 계약을 확정해야 합니다. 합성·구현 및 정확도 스크립트의 성공 판정도 보강이 필요합니다.

| 심각도 | 치명 | 중요 | 경미 | 참고 | 합계 |
|---|---:|---:|---:|---:|---:|
| 독립 발견 사항 | 0 | 6 | 7 | 3 | 16 |

치명은 현재 지원 구성의 정상 입력에서 재현되는 기능 실패 또는 명백한 가이드 위반, 중요는 통합 계약·검증 판정·제출에 직접 영향을 주는 항목으로 분류했습니다. 조건부 동작과 추가 확인 사항은 표에 표시했습니다.

기준은 커밋 `74c88dd`의 제출 RTL 6개, 현재 생성된 BRAM IP 설정, 기준 문서 5종 및 과제 가이드 원문입니다. 조원1(A) 후처리, 조원2(B) 메모리, 조원3(C) PE 배열, 조원4(D) 제어기와 통합·어댑터를 검토했습니다. 수치 판정에는 골든 v2의 shift 11/7을, 외부 인터페이스 판정에는 v0.2와 현재 코드가 각각 약속하는 동작을 적용했습니다. 먼저 독립 발견 사항을 확정한 뒤 이전 리뷰를 열었습니다. 검증은 코드 읽기와 파일을 쓰지 않는 Python 분석으로 수행했습니다.

## 발견 사항

| ID | 심각도 | 위치(파일:줄) | 내용 | 근거 | 재현 방법 | 수정 제안 |
|---|---|---|---|---|---|---|
| D01 | 중요 | `rtl/npu_ctrl.v:175`, `rtl/npu_ctrl.v:198`, `rtl/npu_ctrl.v:228`, `rtl/npu_mem_ctrl.v:72`, `tb/tb_npu_top.v:134` | v0.2 §6-1처럼 `o_done`만 기다리는 호스트는 첫 읽기를 잃을 수 있음 | 마지막 GO의 상승 엣지에서 `o_done=1`과 `S_DONE`이 함께 설정됨. 다음 상승 엣지에서 OMEM[9]가 기록되고 IDLE로 넘어감. 그 에지 직전까지 busy=1이어서 외부 읽기와 start가 수락되지 않음. 현재 TB는 두 신호를 함께 확인 | DONE 구간에 OMEM 읽기 또는 start를 한 클럭 요청. 첫 IDLE 구간에서 같은 요청을 반복해 수락 여부 비교. 읽기 응답이 우연히 이전 값과 같을 수 있으므로 BRAM req도 확인 | 완료를 최종 쓰기와 같은 엣지에 공표하고 busy도 함께 해제하거나, 호스트 계약과 스펙 예시를 `!o_busy && o_done`으로 통일 |
| D02 | 중요 | `rtl/npu_mem_ctrl.v:22`, `rtl/npu_mem_ctrl.v:88`, `rtl/npu_mem_ctrl.v:185`, `rtl/memory_controller.v:84`, `rtl/memory_controller.v:125`, `docs/과제가이드_요구사항_체크.md:14` | 현재 호스트 주소 맵은 v0.2 §3과 호환되지 않음. **확인 필요** — 제출에서 COE 초기화만 써도 되는지 | v0.2의 번호 0/1은 WMEM/BIAS 쓰기, 번호 4는 OMEM. 실제 번호 0/1은 쓰기 무시·읽기 0, 번호 2/3/4/5는 IMEM_A/ACT_A/ACT_B/OMEM. 번호 4에 결과 읽기를 하면 ACT_B를 읽음. 가이드 p.3은 데이터 적재용 hex를 요구하며 적재 경로까지 명시하지는 않음 | idle에서 번호 0/1로 쓰기를 디코드하고 WMEM/BMEM의 `wea=0` 확인. 번호 4와 5의 읽기 MUX 대상 비교 | 최종 주소·깊이·읽기/쓰기 권한을 문서와 TB에 반영. 가중치/바이어스 호스트 적재가 요구되면 4뱅크 및 128b 라인으로 쓰는 경로 추가 |
| D03 | 중요 | `run_sim.tcl:57`, `run_sim.tcl:99`, `run_impl.tcl:36`, `rtl/npu_top.v:18`, `rtl/npu_mem_ctrl.v:166`, `team_originals/B_memory_controller_1112/ip/wmem_bank0.xci:44` | 재사용 프로젝트의 IP와 RTL 지연을 합성 전에 함께 검증하지 않음 | 현재 생성 IP는 10개 모두 지연 1. 조원2(B) 원본 WMEM 4개와 BMEM은 지연 2. `run_impl.tcl`은 프로젝트를 열고 기본 RD_LAT=1로 합성하는 흐름에 IP 검사 없음. `run_sim.tcl` 재사용 검사는 primitive 출력 레지스터만 보며 core 출력 레지스터, 실제 깊이·폭 및 COE 변경은 검사하지 않음 | **정적/Python 재현.** WMEM만 실제 지연 2가 되면 FC1 뉴런 0의 k=50에서 `x=5c2a0000`에 현재 `w=05050108` 대신 k=49의 `w=09080403` 결합. 해당 네 항의 합은 670 대신 1,164 | 시뮬과 합성의 공통 사전 검사에서 IP 10개, 읽기 지연·폭·깊이·초기화 데이터와 RTL 파라미터를 확인. 제출 구성은 OFF/RD_LAT=1로 확정 |
| V01 | 중요 | `tb/tb_npu_top.v:103`, `tb/tb_npu_top.v:143`, `tb/tb_npu_top.v:159`, `tb/tb_npu_top.v:167`, `tb/tb_npu_top.v:188` | 단독 통합 TB가 유효한 시험 데이터와 실행 장수를 확인하지 않음 | 비교 연산 `!==`는 한쪽만 X면 잡지만 양쪽의 X 패턴이 같으면 일치로 처리. 라벨은 정확도 집계에만 쓰므로 X나 범위 밖 라벨도 TB FAIL 조건에 포함되지 않음. `N_IMG=0`이면 루프를 건너뛰어 `n_pass == N_IMG`가 참 | 단독 TB 조건식에 `N_IMG=0` 대입. 또는 라벨만 누락된 경우 `nerr_img` 계산에 라벨 항목이 없는지 추적. 이미지 분류 오답은 정상 모델에서도 발생할 수 있음 | 양수 장수·범위와 골든 파일 유효 비트·라벨 0~9를 먼저 검사하고, 비교 양쪽에 X/Z를 별도로 거부. 비트 일치 및 정확도 집계는 별도 유지 |
| V02 | 중요 | `run_impl.tcl:63`, `run_impl.tcl:137`, `run_impl.tcl:146` | 타이밍 실패가 프로세스 성공으로 보고됨 | WNS 또는 WHS가 음수여도 메시지만 찍고 `exit 0`으로 종료. 검사 경로 유무를 최종 판정에 명시하지 않고, 가이드 p.5의 양수 조건에 `>= 0`을 적용 | 예를 들어 WNS=-0.1, WHS=+0.05를 조건에 대입하면 NOT MET를 출력한 뒤 종료 코드 0에 도달 | setup/hold 경로 존재와 양수 slack을 명시적으로 검사해 요약·리포트는 보존하고 실패 시 0이 아닌 코드 반환 |
| V03 | 중요 | `scripts/run_accuracy.sh:40`, `scripts/run_accuracy.sh:50`, `scripts/run_accuracy.sh:55`, `scripts/review/xrun.sh:43`, `scripts/accuracy_report.py:39`, `scripts/accuracy_report.py:65` | 정확도 재개 시 BRAM IP가 바뀌어도 완료 로그가 재사용될 수 있음. 집계도 묶음 종료를 검증하지 않음 | 스탬프에는 RTL·TB·일부 골든만 포함. 새 스냅샷이 읽는 생성 IP의 Verilog/MIF는 빠짐. 묶음의 PASS/FAIL 표식으로 기존 로그를 건너뛰며 실행 종료 코드가 저장 조건에 없음. 집계는 각 이미지 레코드만으로 PASS 가능 | 스탬프 식에서 MIF 변경 전후 입력이 같은지 확인. Python 메모리 내 로그에 이미지 1장의 유효 PASS 줄만 주고 TB 최종 PASS 줄을 빼도 집계 함수가 0을 반환함을 확인 | 실제 컴파일 소스·정의·BRAM 초기화까지 스탬프에 포함. 각 묶음의 기대 구간, 완료 표식과 성공 종료를 재사용 및 최종 집계 조건으로 검사 |
| D04 | 경미 | `rtl/npu_mem_ctrl.v:72`, `rtl/npu_mem_ctrl.v:180`, `tb/review/npu_checker.v:213`, `tb/review/npu_checker.v:391` | 읽기 요청 유무와 무관하게 출력 MUX 선택을 갱신. **확인 필요** — 응답이 없는 구간에 `o_dout`을 0 또는 유지로 정의할지 | busy 중 외부 BRAM 명령은 막히지만 내부 BRAM 출력이 `o_dout`에 전달될 수 있음. CEN 비활성이나 외부 쓰기 중에도 선택이 바뀜. A11은 수락된 읽기만 검사하며 busy 중 토글은 관찰 카운트 | FC2 동안 CEN=1, 번호 3을 유지하면 ACT_A 내부 읽기 데이터가 MUX로 나옴. 앞 엣지에 수락된 idle 읽기는 같은 엣지에 start를 받아도 응답해야 함 | 무효 구간 동작이 필요하면 **수락된 읽기**의 valid와 선택을 함께 한 클럭 지연해 MUX를 제어. 현재 busy의 조합 게이팅만 쓰면 start와 동시에 수락한 읽기 응답까지 사라질 수 있음 |
| D05 | 경미 | `rtl/npu_mem_ctrl.v:88`, `rtl/npu_mem_ctrl.v:94`, `rtl/npu_mem_ctrl.v:99`, `rtl/npu_mem_ctrl.v:104`, `tb/review/tb_edge.v:327` | 범위 밖 외부 주소가 유효 줄에 별칭으로 쓰이거나 BRAM 논리 깊이를 넘음 | 디코더는 주소 하위 8/7/5/4비트만 사용. IMEM_A 0x100은 0에, OMEM 0x10은 0에 접근. IMEM_A 196~255와 OMEM 10~15는 IP 깊이 밖. 현재 주석은 합법 주소만 허용 | idle에서 IMEM_A 0x100에 쓰고 0을 읽는 조건을 디코더 식에 대입. 범위 밖 요청을 S11에서 관찰 | 범위 검사는 슬라이싱 전 전체 17비트에 적용. 무효 접근 거부 정책과 ACT/OMEM 외부 쓰기 허용 여부를 인터페이스에 명시 |
| D06 | 경미 | `rtl/memory_controller.v:86`, `rtl/memory_controller.v:127`, `rtl/memory_controller.v:213`, `rtl/npu_mem_ctrl.v:115` | 조원2(B) 단독 WMEM/BMEM valid가 OFF IP의 데이터보다 1클럭 늦음 | req를 2단 지연. 통합에서는 해당 valid가 미사용이고 조원4(D)의 valid/bias_we로 데이터를 샘플링. 실제 BRAM은 req와 무관하게 항상 읽음 | 연속 두 주소에 대해 한 클럭 req를 주는 시간표를 작성하면 OFF IP의 첫 데이터는 req+1, valid는 req+2 | 조원2(B)의 최종 인터페이스에서 유효 신호를 실제 IP 지연과 일치시키거나 미사용 출력으로 정리. 읽기 enable을 게이트할 경우 BMEM의 선행 읽기와 RD_LAT=2 파이프라인까지 검증 |
| D07 | 경미 | `rtl/npu_ctrl.v:89`, `rtl/npu_ctrl.v:121`, `rtl/npu_ctrl.v:238`, `rtl/npu_mem_ctrl.v:166` | 문서상 1/2 이외의 RD_LAT 값이 거부되지 않음 | 3은 D가 3클럭 늦추고 어댑터는 1클럭 경로 사용. 4는 2비트 WAIT 카운터가 4에 도달할 수 없어 정지. 0은 시프트 레지스터 범위 밖 비트 선택 | Python으로 `0,1,2,3,0,…` WAIT 카운터와 데이터 경로 선택을 계산 | 최종 빌드에서 1을 고정하거나 설정 검사에서 1/2만 허용하고 IP 지연과 함께 검증 |
| V04 | 경미 | `team_originals/golden_v2_1110/golden_v1.py:179`, `team_originals/golden_v2_1110/golden_v1.py:188`, `team_originals/golden_v2_1110/README.txt:18`, `team_originals/golden_v2_1110/out/summary.txt:3` | 골든 재생성 기본값이 v2의 학습셋 보정 계약과 다름 | `--select` 기본값은 `test`. 이 경우 평가할 테스트셋에서 289개 shift 조합을 고르므로 같은 데이터로 최종 성능을 평가하게 됨. 현재 v2 산출물은 `train`과 11/7 기록이 있고 README 재현 명령도 train을 명시 | 인자 생략 시 선택 데이터와 최종 측정 양쪽이 `te_x/te_y`를 쓰는 경로를 추적 | 기본값을 train으로 맞추거나 선택을 필수 인자로 만들고 산출물에 보정 데이터와 shift를 기록 |
| V05 | 경미 | `run_sim.tcl:132`, `run_sim.tcl:175`, `tb/tb_npu_ctrl.v:18`, `tb/tb_npu_top.v:59`, `run_regress.sh:115` | `oreg_on`의 단위 TB와 통합 TB가 다른 지연으로 실행됨 | `run_sim.tcl`은 OREG_ON만 정의. top TB는 이를 보고 2를 고르지만 ctrl TB는 TB_RD_LAT가 없으면 1. 전체 회귀에는 RD_LAT=2 단위 검사가 별도로 있음 | `oreg_on` 설정에서 두 TB의 전처리 정의와 기대 클럭 수를 추적 | 비교 모드를 유지하면 ctrl에 `TB_RD_LAT=2`도 전달하고 로그에 두 설정을 기록 |
| D08 | 경미 | `rtl/memory_controller.v:4`, `rtl/memory_controller.v:200`, `rtl/npu_pe_array.v:34`, `rtl/npu_top.v:41`, `rtl/npu_top.v:62` | 이름 규칙 PDF와 최종 구성의 모듈·신호 표가 일부 다름 | 조원2(B)의 하위 래퍼는 `clk/rst` 및 동기 active-high를 사용하고 어댑터가 변환. 조원3(C)의 내부 레지스터에 `r_` 접두사가 빠짐. 규칙 §3의 `waddr`는 B에 연결되지 않고 뱅크 주소/선택과 `rd_en`이 사용됨. 실제 폭은 일치 | 모듈 선언과 top 인스턴스 연결을 이름 규칙 §§1~3과 대조 | 최종 B 계층과 4뱅크 포트를 팀 연결 표에 반영. 제출 이름 규칙이 하위 모듈에도 엄격히 적용되는지 확정 |
| R01 | 참고 | `rtl/npu_ctrl.v:126`, `rtl/npu_ctrl.v:140`, `rtl/npu_mem_ctrl.v:72`, `tb/review/tb_edge.v:130`, `tb/review/tb_edge.v:296` | reset 중 메모리 쓰기와 start 유지의 호스트 동작 | reset으로 busy=0이 되어 외부 쓰기는 가능하고 BRAM 내용은 유지. 연산 제어와 파이프라인은 리셋됨. S01이 reset 중 이미지 쓰기를 의도적으로 사용. start를 첫 IDLE 엣지까지 1로 유지하면 새 실행을 수락 | reset 중 CEN/WEN을 0으로 하여 `w_ext_we=1` 확인. start를 DONE 이후에도 유지하고 IDLE 전이식을 추적 | 메모리 유지와 reset 중 외부 접근, 1클럭 start 펄스를 최종 계약에 명시. 보드 리셋 해제 조건은 R02 참조 |
| R02 | 참고 | `constr/npu_top.xdc:7`, `reports/impl_timing_summary.rpt:92`, `reports/impl_timing_summary.rpt:146`, `reports/review/drc_routed.rpt:37` | 내장 클럭의 STA와 보드 입출력 검증 범위가 다름. **확인 필요** — 실제 보드에서의 타이밍 및 동작 | 기존 보고서의 10 ns 내부 분석은 WNS +2.553 ns, WHS +0.054 ns. 입력 47개, 출력 34개 지연 미지정. DRC에 82개 포트의 NSTD-1/UCIO-1이 있어 현재 제약으로 비트스트림 생성 불가 | 저장된 리포트의 no_input_delay/no_output_delay 및 DRC 항목을 읽음 | 수치에는 내부 경로 범위를 표기. 보드 사용 시 실제 연결 기준으로 핀·IOSTANDARD·입출력 타이밍과 비동기 리셋 해제를 검증 |
| R03 | 참고 | `rtl/npu_postproc.v:50`, `tb/tb_npu_top.v:139`, `scripts/review/gen_stress.py:34`, `run_regress.sh:119` | MNIST 벡터만으로 포화 분기를 검증할 수 없음. 현재 정식 회귀에는 보완 벡터가 있음 | 독립 계산 100장 및 10,000장에서 shift 후 127 초과가 두 레이어 모두 0회. FC1 뉴런 229의 양수 가중치 위치에만 127을 넣으면 sum=682,373, shift 결과 333, 기대 출력 127 | Python에서 지정 뉴런의 양수 가중치 합에 127을 곱하고 bias를 더함. FC1 sum=262,143/262,144 또는 FC2 sum=16,383/16,384로 포화 직전/진입 확인 | 실제 합성 이미지 회귀를 제출 검증에 포함하고 조원1(A) 단위에서 두 shift의 경계값을 직접 검사 |

## 독립 검토 근거

### FSM, 데이터 경로, 정수 연산

- `rtl/npu_ctrl.v:99`과 `:126`의 전이 및 포인터식을 Python으로 옮겨 두 지연 구성의 전 클럭을 추적했습니다. 레이어별 ISSUE 길이 196/128/32, GO 512/128/10, bias_we 650회, 총 읽기 117,056회와 쓰기 128/32/10회를 확인했습니다. 마지막 유효 단일 WMEM 주소는 117,055, 뱅크 주소는 29,279, bias 번호는 649입니다. ISSUE 사이에도 WMEM은 최대 29,279, BMEM 라인은 최대 162입니다. bias 포인터가 끝에 650이 되어도 같은 BMEM 라인 162에 속합니다.
- 마지막 ISSUE를 클럭 `t`라 두면 마지막 valid는 `t+RD_LAT`에 C의 곱 레지스터에 샘플되고 다음 엣지에서 누산됩니다. GO는 `t+RD_LAT+2`에 A가 누산값을 샘플하는 동시에 C를 클리어합니다. 직전 뉴런의 GO 또는 reset이 누산기를 먼저 0으로 만들므로 start에서 별도 clear가 없어도 됩니다. A의 쓰기와 D의 주소는 GO 다음 클럭에 맞습니다.
- 전환 클럭에는 이전 레이어 번호가 남아 최종 결과가 ACT_A[127], ACT_B[31]에 각각 먼저 기록됩니다. 다음 엣지부터 새 레이어가 결과 메모리를 읽습니다. 마지막 OMEM[9] 쓰기까지 합한 모델의 start 수락 엣지부터의 간격은 RD_LAT=1에서 119,009클럭, 예전 WMEM/BMEM만 2클럭인 구성에서 119,659클럭입니다. busy 중 외부 읽기/쓰기 요청은 메모리 포트를 얻지 않습니다. 동일 엣지의 마지막 입력 쓰기와 start는 직전까지 IDLE이므로 둘 다 수락 가능합니다.
- `rtl/npu_top.v:35`~`:79`의 네 블록 연결을 양쪽 포트 선언과 대조했습니다. 데이터선 32b, 레이어 및 lane 2b, shift 5b, 뱅크 주소 15b 및 선택 2b, bias 번호 10b가 의도와 맞습니다. 어댑터의 주소 슬라이싱은 내부 주소 범위에 맞습니다. 조합 블록의 기본값과 각 레지스터의 드라이버를 점검해 latch, 조합 루프, 다중 드라이버를 발견하지 않았습니다.
- `rtl/npu_pe_array.v:28`~`:55`에서 두 입력의 각 바이트를 signed int8로 해석하고 s16 곱, s17/s18 트리, s32 누산에 넣습니다. signed int8 전체 범위를 써도 한 곱 절댓값은 최대 16,384이고 네 곱의 합 상한은 65,536입니다. 고정 COE의 bias까지 포함한 레이어별 보수적 절댓값 상한은 12,926,606 / 8,388,716 / 2,097,491로 모두 s32 범위 안입니다.
- `rtl/npu_postproc.v:50`~`:55`, `:84`~`:89`, `rtl/npu_ctrl.v:101`~`:103`은 `golden_v1.py:113`~`:127`의 v2 연산과 일치합니다. FC1/FC2는 bias 후 ReLU, 각각 11/7비트 오른쪽 shift로 버림, 127 포화, 하위 바이트부터 4개씩 패킹합니다. FC3는 signed s32 점수입니다. 골든 생성기의 가중치와 bias 반올림은 오프라인 양자화에 적용됩니다.
- 기존 팀의 PASS 로그나 생성 코드를 실행하는 대신 Python에서 COE를 직접 풀었습니다. 식 `bank=n%4, row=bank_base+(n//4)*L+k`로 재배열한 117,056개 가중치 워드와 650개 bias가 v2 원본 hex와 일치했습니다. `hex/`의 100장으로 다시 계산한 FC1 12,800워드, FC2 3,200워드, FC3 1,000워드가 전부 비트 일치했고 라벨은 100/100이었습니다. v2 개별 hex 10장과 연결된 통합 파일도 일치했습니다. 2단계에서 로컬 MNIST 원본으로 추가 확인한 첫 100장의 `pixel >> 1` 및 라벨은 통합 입력과 일치했습니다. COE 기반 정수 추론을 테스트셋 10,000장에 적용한 결과 9,930/10,000(99.30%)이며 FC3 최댓값 동점은 0건입니다. 이 수치는 Python 모델 결과입니다.

### 과제 가이드 및 생성 IP

| 가이드 항목 | 판정 | 직접 확인한 근거 |
|---|---|---|
| p.4~5 `initial`, 지연문, `$readmemh/$readmemb` 제한 | 충족 | `rtl/*.v` 6개에서 주석·문자열과 파라미터 전달 문법을 제외해 전수 검사. 금지 구문 0건. `sim_models/`는 별도 행동 모델이므로 제출 RTL 소스 목록에서 제외 |
| p.5 SRAM을 BMEM으로 구현 | 충족 | RTL에 SRAM용 reg 배열 없음. `rtl/memory_controller.v:84`~`:193`의 메모리 10개와 생성된 Block Memory Generator 8.4 설정이 대응. 레지스터는 제어, 누산, 패킹, 선택 지연에 사용 |
| p.8~9 Native / Single Port RAM 및 Primitives Output Register OFF | 현재 생성 구성 충족 | 활성 프로젝트의 10개 .xci와 생성된 시뮬 래퍼 모두 확인. primitive/core output registers 모두 OFF, Port A 지연 1. 조원2(B) 원본 .xci의 WMEM 4개와 BMEM은 ON으로 그대로 제출하면 p.9와 불일치 |
| p.12 `~CEN = ena`, `~WEN = wea` | 외부에서 접근 가능한 4개 메모리 충족. 고정 ROM 경로의 해석은 확인 필요 | idle·번호 일치 시 CEN/WEN=0/0은 ENA/WEA=1/1, 0/1은 1/0, CEN=1은 0/0. busy 중 외부 명령 대신 내부 req/we를 연결. WMEM/BMEM의 ENA=1, WEA=0은 내부 고정 CEN=0, WEN=1에 해당하는 상시 읽기. 외부 CEN/WEN이나 내부 req에 따른 enable 전환은 없음. IMEM_B는 비활성 |
| p.33 100 MHz XDC 및 p.5 양수 slack | XDC 일치. 저장된 내부 경로 slack 양수 | `constr/npu_top.xdc:7`은 가이드와 동일한 `create_clock -name i_clk -period 10 [get_ports i_clk]`. XPR의 constrs_1에 연결되어 있고 기존 리포트에 setup/hold 양수. 자동 판정 및 보드 범위는 V02/R02 |

활성 프로젝트의 `vivado_sim/aissd_D_sim.srcs/sources_1/ip/<IP>/<IP>.xci` 전체를 읽었습니다. 공통 설정은 Native, Single_Port_RAM, WRITE_FIRST, Use_ENA_Pin, 1비트 WEA(바이트 쓰기 OFF)입니다. 읽기·쓰기 폭 및 깊이는 양쪽이 같습니다. 아래 경로는 각 .xci가 실제로 참조하는 저장소 안 파일입니다.

| IP | 개수 | 폭 × 깊이 | 주소 폭 | COE 경로와 검증 |
|---|---:|---|---:|---|
| wmem_bank0~3 | 4 | 32 × 29,280 각각 | 15b | `coe/weight_bank0.coe`~`coe/weight_bank3.coe`. 각각 29,280워드 |
| bmem_128 | 1 | 128 × 163 | 8b | `coe/bias_128bit.coe`. 163라인, 하위 32b부터 4개 lane |
| imem_a_bram / imem_b_bram | 2 | 32 × 196 각각 | 8b | Load_Init_File=false. A만 통합에서 사용 |
| act_a_bram | 1 | 32 × 128 | 7b | Load_Init_File=false |
| act_b_bram | 1 | 32 × 32 | 5b | Load_Init_File=false |
| omem_bram | 1 | 32 × 10 | 4b | Load_Init_File=false |

- 초기화가 있는 5개의 `Coe_File`은 각 .xci 기준 `../../../../../coe/…`로 해석됩니다. 모두 파일이 존재하고, Python에서 COE와 `vivado_sim/aissd_D_sim.gen/sources_1/ip/`의 동명 바이너리 MIF를 워드별 비교해 전부 일치했습니다. 위 설정은 `run_sim.tcl:57`~`:92`의 기본 생성 경로와 일치합니다.
- `run_impl.tcl:38`~`:43`, `:94`~`:136`은 top을 `npu_top`으로 지정하고 IP OOC 합성, top 합성, 배치·배선을 실행하도록 구성됩니다. `vivado_sim/aissd_D_sim.xpr:372`와 생성된 `vivado_sim/aissd_D_sim.runs/synth_1/npu_top.tcl:134`은 대상 `xck26-sfvc784-2LV-c`와 Vivado 기본 합성 설정에 부합합니다. DSP 강제 옵션은 없고 기존 구현 결과는 DSP 0입니다. 곱셈을 LUT로 매핑한 것은 가이드 위반 근거가 없습니다. 프로젝트 재사용 검증과 타이밍 종료 판정은 D03/V02에 정리했습니다.

## 이전 리뷰와의 비교

비교 기준은 `docs/review_1114.md`의 R01~R20, §§2~3입니다. 아래 비교는 위 16건과 별도로 집계하지 않았습니다.

### 이전 리뷰가 놓친 것

| 이번 항목 | 차이 |
|---|---|
| D03 | 이전 §2-3은 두 IP 세트의 차이를 확인했습니다. 이번에는 지연이 다른 IP가 합성 흐름에 섞이는 경로와, 재사용 검사에서 core output register·폭·깊이·초기화가 빠진 점을 확인했습니다. |
| V01 | (0장 실행, 기대값과 실제값의 동일 X 패턴, 라벨 데이터의 유효성)은 기존 리뷰의 벡터 커버리지와 별개인 성공 판정 구멍입니다. |
| V02 | 이전 §3-6은 합성 스크립트에서 문제를 발견하지 못했다고 했습니다. 현재 파일에서 타이밍 NOT MET 이후에도 종료 코드 0이 유지되는 경로를 확인했습니다. |
| V03 | 정확도 재개 로그와 현재 빌드의 IP/MIF 사이에 연결 근거가 빠져 있습니다. 묶음 최종 PASS 표식 없이도 집계가 성공하는 경우를 메모리 내 로그로 확인했습니다. |
| V04, V05 | v2 골든 재생성 기본값이 테스트셋 보정을 선택하는 점과 `oreg_on`의 단위·통합 TB 파라미터 차이를 추가로 확인했습니다. |

### 이견과 달라진 상태

- **완료 신호의 심각도.** 이전 R05는 경미였으나, v0.2 §6-1을 따르는 호스트의 합법적인 첫 읽기가 유실되므로 중요(D01)로 분류했습니다. §6-2/§6-5의 DONE 타이밍 표는 RTL과 일치하고, 최신 README와 TB는 busy도 기다리는 규칙을 이미 사용합니다.
- **출력 MUX 보완 방법.** 이전 R10은 `w_ext_en`으로 선택을 유지하는 방안을 제시했습니다. BRAM 출력 자체가 내부 읽기로 바뀔 수 있으므로 선택 레지스터의 enable만으로는 busy 출력 억제를 보장할 수 없습니다. 응답 억제가 계약에 필요하면 수락된 읽기 valid를 지연해야 합니다(D04).
- **검사 공백의 현재 상태.** 이전 R08의 단위 TB 타임아웃과 장당 클럭 수 미검사는 현재 `tb/tb_npu_ctrl.v:92`~`:108`, `tb/tb_npu_top.v:167`, `:194`~`:199`에서 보강됐습니다. P6의 `run_sim.tcl` TB 실패 종료 코드, 유연한 인자 처리, HEX_DIR 치환 실패 검출도 현재 코드에 반영됐습니다. README의 DRC 문구(R07) 역시 갱신됐습니다.
- **SDF와 주파수 결론의 범위.** 이전 §2-8의 지연 포함 시뮬 실패는 **확인 필요**입니다. 저장된 최소 실험은 XSim의 SDF 적용 차이 가설을 뒷받침하지만 설계·제약·도구 원인을 확정할 수준까지 이번에 확인하지 못했습니다. §3-5의 약 134 MHz는 기존 내부 setup 여유에서 계산한 값이며, 확인된 제약은 100 MHz입니다.
- **MNIST 기준 데이터.** 이전 R17에는 원본이 없다고 기록돼 있습니다. 이번에는 로컬 원본으로 100장 입력·라벨과 COE 기반 10,000장 정수 정확도 99.30%를 독립 확인했습니다.

### 공통 발견

- 이전 R04~R06, R09~R10, R14~R15, R18~R19의 주소 맵·COE 전용 적재, done/busy 차이, level start, 범위 밖 주소 별칭, busy 중 `o_dout` 반영, 파라미터 범위, 보드 제약, 항상 읽는 WMEM/BMEM, OFF 구성의 B 단독 valid 문제를 코드에서 다시 확인했습니다.
- 이전 R01~R03의 단독 golden TB 제약을 확인했습니다. 입력 첫·마지막 줄은 100장 전부 0이며 포화가 없고, 단독 TB는 연산 중 외부 요청을 구동하지 않습니다. 현재 `run_regress.sh:119`~`:133`은 합성 이미지, `tb_edge`, 매 클럭 검사기를 정식 회귀에 포함합니다. 일부 에지 동작은 여전히 `OBSERVE`로 남아 최종 PASS를 좌우하지 않습니다.
- 카운터 경계, 레이어 간 쓰기/읽기 순서, 단일 `waddr`의 검증용 역할, 지원 RD_LAT의 정렬 및 연결 폭에 대해서는 이전 §§2-1~2-4와 같은 결론입니다. 과제 가이드의 금지 구문, BMEM 사용, OFF 출력 레지스터, 10 ns XDC도 생성 설정을 기준으로 일치합니다.

## 검증 범위

현재 생성 설정과 소스를 확인했고, 기록된 타이밍·DRC 리포트는 이전 산출물로 인용했습니다. Vivado, xsim, 다른 HDL 시뮬레이터, 합성 및 구현은 실행하지 않았습니다. 이번 검수에서 실행 중인 RTL 정확도 작업이나 SDF 결과를 재검증하지 않았습니다. 과제 가이드 원문은 제공된 1~39쪽 기준이며 COE 적재의 제출 인정 여부와 추가 요건은 **확인 필요**입니다.

