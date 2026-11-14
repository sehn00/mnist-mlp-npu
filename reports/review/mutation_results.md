# 버그 주입(뮤테이션) 결과

원본 rtl/ 은 그대로 두고 복사본(build/review/mut/<ID>/rtl)에 버그를 하나씩 넣어 돌린 결과. 스크립트: scripts/review/mutate.py, run_mutants.sh

- unit = 기존 tb_npu_ctrl, top = 기존 tb_npu_top(golden 2장), chk = 같은 시뮬에 붙인 npu_checker 에러 수
- stress / edge 는 top 을 통과한(PASS) 뮤턴트만 추가로 돌림 (stress = 기존 tb_npu_top + 합성 이미지 16장, edge = tb_edge + 체커)
- HANG = 정해 둔 시뮬레이션 시간 안에 TB 가 끝나지 않음 (tb_npu_ctrl 에는 타임아웃이 없음)

| ID | 파일 | 넣은 버그 | 예상 | unit | top | chk | stress | edge | 기존 TB 판정 |
|---|---|---|---|---|---|---|---|---|---|
| D01 | npu_ctrl.v | shift FC1 11 -> 10 | detect | FAIL | FAIL | 1674 | - | - | 잡음 |
| D02 | npu_ctrl.v | shift FC2 7 -> 8 | detect | FAIL | FAIL | 305 | - | - | 잡음 |
| D03 | npu_ctrl.v | L FC2 128 -> 127 (줄 하나 덜 읽음) | detect | FAIL | FAIL | 96816 | - | - | 잡음 |
| D04 | npu_ctrl.v | N FC3 10 -> 9 (마지막 뉴런 빠짐) | detect | FAIL | FAIL | 12 | - | - | 잡음 |
| D05 | npu_ctrl.v | N FC1 512 -> 511 | detect | FAIL | FAIL | 110711 | - | - | 잡음 |
| D06 | npu_ctrl.v | o_valid 1클럭 늦음 | detect | FAIL | PASS | 5338 | - | - | 잡음 |
| D07 | npu_ctrl.v | o_valid 1클럭 빠름 | detect | FAIL | FAIL | 5620 | - | - | 잡음 |
| D08 | npu_ctrl.v | o_bias_we 1클럭 늦음 | benign | FAIL | PASS | 0 | - | - | 잡음 |
| D09 | npu_ctrl.v | o_bias_we 1클럭 빠름 | detect | FAIL | FAIL | 2868 | - | - | 잡음 |
| D10 | npu_ctrl.v | go 1클럭 빠름 (WAIT 1클럭 짧음) | detect | FAIL | FAIL | 1570 | - | - | 잡음 |
| D11 | npu_ctrl.v | go 1클럭 늦음 (WAIT 1클럭 김) | benign | FAIL | PASS | 1302 | - | - | 잡음 |
| D12 | npu_ctrl.v | o_lane 순서 뒤집힘 (3 - n%4) | detect | FAIL | FAIL | 2814 | - | - | 잡음 |
| D13 | npu_ctrl.v | o_wbank_sel = n%4 + 1 | detect | FAIL | FAIL | 470820 | - | - | 잡음 |
| D14 | npu_ctrl.v | o_wbank_addr + 1 | detect | FAIL | FAIL | 470818 | - | - | 잡음 |
| D15 | npu_ctrl.v | o_xaddr + 1 | detect | FAIL | FAIL | 506896 | - | - | 잡음 |
| D16 | npu_ctrl.v | o_baddr + 1 | detect | FAIL | FAIL | 237310 | - | - | 잡음 |
| D17 | npu_ctrl.v | o_oaddr + 1 (FC1/FC2) | detect | FAIL | FAIL | 21027 | - | - | 잡음 |
| D18 | npu_ctrl.v | o_oaddr FC3 도 n/4 | detect | FAIL | FAIL | 46 | - | - | 잡음 |
| D19 | npu_ctrl.v | FC3 wbank_base 29184 -> 29185 | detect | FAIL | FAIL | 1336 | - | - | 잡음 |
| D20 | npu_ctrl.v | FC2 relu_en = 0 | detect | FAIL | FAIL | 360 | - | - | 잡음 |
| D21 | npu_ctrl.v | o_fc3 항상 0 | detect | FAIL | FAIL | 68 | - | - | 잡음 |
| D22 | npu_ctrl.v | 뱅크 포인터 되돌림 조건 lane != 3 -> != 2 | detect | FAIL | FAIL | 118248 | - | - | 잡음 |
| D23 | npu_ctrl.v | o_acc_clr 항상 0 | detect | FAIL | FAIL | 3898 | - | - | 잡음 |
| D24 | npu_ctrl.v | o_waddr + 1 (top 에서는 안 쓰는 출력) | benign | FAIL | PASS | 468202 | - | - | 잡음 |
| D25 | npu_ctrl.v | LAYER 에서 wbank 포인터 다시 안 넣음 | equiv | PASS | PASS | 0 | - | - | 동작 같음 |
| D26 | npu_ctrl.v | o_done 이 1클럭만 1 (유지 안 함) | detect | FAIL | TIMEOUT | 2 | - | - | 잡음 |
| D27 | npu_ctrl.v | o_busy 가 DONE 클럭에 0 (1클럭 일찍 내려감) | detect | PASS | FAIL | 13 | - | - | 잡음 |
| D28 | npu_ctrl.v | o_rd_en 이 WAIT 에서도 1 | benign | FAIL | PASS | 15276 | - | - | 잡음 |
| B01 | npu_mem_ctrl.v | busy 중 외부 쓰기를 IMEM 으로 통과시킴 | detect | n/a | PASS | 0 | - | - | 못 잡음 |
| B02 | npu_mem_ctrl.v | FC2 결과 쓰기 대상 레이어 번호 틀림 | detect | n/a | FAIL | 451 | - | - | 잡음 |
| B03 | npu_mem_ctrl.v | ACT_A 쓰기 주소에 xaddr 사용 | detect | n/a | FAIL | 12884 | - | - | 잡음 |
| B04 | npu_mem_ctrl.v | WMEM 뱅크 MUX: 뱅크 0 자리에 뱅크 1 | detect | n/a | FAIL | 59622 | - | - | 잡음 |
| B05 | npu_mem_ctrl.v | bias 4개 묶음에서 0번 자리에 1번 | detect | n/a | FAIL | 1134 | - | - | 잡음 |
| B06 | npu_mem_ctrl.v | FC2 입력을 IMEM 에서 읽음 | detect | n/a | FAIL | 12456 | - | - | 잡음 |
| B07 | npu_mem_ctrl.v | BMEM 주소를 /4 하지 않음 | detect | n/a | FAIL | 91576 | - | - | 잡음 |
| B08 | npu_mem_ctrl.v | 외부 읽기 MUX: ACT_A 자리에 ACT_B | detect | n/a | FAIL | 45 | - | - | 잡음 |
| B09 | npu_mem_ctrl.v | 외부 IMEM 주소 7비트만 사용 | detect | n/a | FAIL | 53800 | - | - | 잡음 |
| B10 | npu_mem_ctrl.v | WMEM 뱅크 선택을 지연 없이 사용 | equiv | n/a | PASS | 0 | - | - | 동작 같음 |
| A01 | npu_postproc.v | 포화 기준 127 -> 1000 (사실상 포화 없음) | detect | n/a | PASS | 0 | - | - | 못 잡음 |
| A02 | npu_postproc.v | 묶기 레인 0 과 3 자리 바뀜 | detect | n/a | FAIL | 612 | - | - | 잡음 |
| A03 | npu_postproc.v | ReLU 없음 | detect | n/a | FAIL | 818 | - | - | 잡음 |
| A04 | npu_postproc.v | bias 안 더함 | detect | n/a | FAIL | 683 | - | - | 잡음 |
| A05 | npu_postproc.v | o_we 를 lane 2 에서 냄 | detect | n/a | FAIL | 1514 | - | - | 잡음 |
| A06 | npu_postproc.v | 포화 값 127 -> 126 | detect | n/a | PASS | 0 | - | - | 못 잡음 |
| C01 | npu_pe_array.v | x 레인 1 자리에 레인 2 | detect | n/a | FAIL | 2600 | - | - | 잡음 |
| C02 | npu_pe_array.v | 덧셈 트리에서 p3 빠짐 | detect | n/a | FAIL | 2600 | - | - | 잡음 |
| C03 | npu_pe_array.v | 가중치를 부호 없는 수로 곱함 (레인 3) | detect | n/a | FAIL | 2600 | - | - | 잡음 |
| C04 | npu_pe_array.v | 누산을 v1 이 아니라 i_valid 로 (1클럭 어긋남) | detect | n/a | FAIL | 288 | - | - | 잡음 |
| C05 | npu_pe_array.v | acc_clr 보다 누산 우선 | equiv | n/a | PASS | 0 | PASS | PASS (chk 0) | 동작 같음 |

기능 버그(예상 detect) 42개 중 기존 TB 두 개가 잡은 것: 39개. 못 잡은 것: B01, A01, A06
