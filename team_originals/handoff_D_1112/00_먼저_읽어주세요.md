# D 블록(조원4) 인수인계 · 2026-11-12

## 1. 한 줄 요약
A(후처리), B(메모리), C(PE 배열)는 각자 단위 테스트를 통과했습니다. 남은 건 이 셋을 순서대로 움직이게 하는 **D(컨트롤러, npu_ctrl)** 와 넷을 연결하는 **npu_top** 입니다. D가 들어와야 칩 전체가 돌아갑니다.

## 2. 현재 진행 상황
| 블록 | 담당 | 상태 |
|---|---|---|
| A npu_postproc (bias, ReLU, shift, 포화, 4개 묶기) | 조원1 | ✓ 단위 TB PASS (golden v2) |
| B npu_mem_ctrl (메모리 7개) | 조원2 | ✓ 메모리 단독 검증 PASS |
| C npu_pe_array (곱셈 4개 + 누산) | 조원3 | ✓ 사진 0 뉴런 650개 golden 일치 |
| D npu_ctrl + npu_top | 조원4 | ○ 작성 필요 |

- 오늘(11/12): D 없이 테스트벤치가 제어 신호를 대신 줘서 A+B+C를 연결해 보는 중
- 그림: `01_아키텍처_진행상황.png`

## 3. 일정
- **11/17(화)**: D 완성 → A+B+C+D 연결, FC1~FC3 전부, 사진 10장 golden 일치
- 11/19: 사진 100장 정확도, 합성·타이밍
- 11/23·26: 중간점검 / 12/7 zip 제출 / 12/8·10 발표

## 4. D가 하는 일 (쉽게)
신경망 계산은 이 3중 for 문입니다. D는 이 for 문을 하드웨어(FSM)로 만든 것입니다.
```
for layer in [FC1, FC2, FC3]:
    for n in 0 .. N-1:          # 뉴런
        C 누산기 0으로 (acc_clr), A에 bias 넣기 (bias_we)
        for k in 0 .. L-1:      # 입력 4개씩
            B에서 입력 x[k], 가중치 w[base + n*L + k] 읽어서 C에 주기 (valid)
        2클럭 기다렸다가 A에 go (lane = n % 4)
```
D는 직접 계산하지 않고 **주소와 신호만** 줍니다.

## 5. 레이어 설정표 (golden v2 기준, 중요)
| 레이어 | 입력 메모리 | L (클럭/뉴런) | N (뉴런) | 가중치 시작 주소 | bias 시작 | shift | ReLU | FC3 모드 | 출력 메모리 / 주소 |
|---|---|---|---|---|---|---|---|---|---|
| FC1 | IMEM | 196 | 512 | 0 | 0 | **11** | 1 | 0 | ACT_A, n/4 (128줄) |
| FC2 | ACT_A | 128 | 128 | 100352 | 512 | **7** | 1 | 0 | ACT_B, n/4 (32줄) |
| FC3 | ACT_B | 32 | 10 | 116736 | 640 | 0 | 0 | 1 | OMEM, n (10줄) |

- 가중치 주소 = 시작 주소 + n × L + k / 입력 주소 = k / bias 주소 = bias 시작 + n
- 최종 숫자 판정(10개 점수 중 최댓값)은 TB에서 OMEM을 읽어서 해도 됩니다.

## 6. 블록 연결 규칙 (타이밍)
뉴런 하나 기준:
1. **시작 클럭**: C `i_acc_clr = 1` (누산기 0), A `i_bias_we = 1` + `i_bias` (BMEM 값)
2. **L클럭 동안**: B에서 x, w 읽어서 C `i_x`, `i_w`, `i_valid = 1`
   - BRAM은 주소를 주고 **1클럭 뒤**에 데이터가 나옵니다(조원2에게 확인). 그래서 `i_valid`도 주소보다 1클럭 늦게 줘야 합니다.
3. 마지막 valid 다음 **2클럭 뒤** C `o_acc`가 최종값 → 그 클럭에 A `i_go = 1`, `i_lane = n % 4`, `i_relu_en`, `i_shift`, `i_fc3`
4. A가 다음 클럭에 `o_we`, `o_wdata`를 냄 → B 출력 메모리에 쓰기 (FC1/FC2는 lane 3일 때만, FC3는 매 뉴런)

## 7. 각 블록 포트 (rtl 폴더 파일 참고)
- **C npu_pe_array**: `i_clk, i_rstn, i_x[31:0], i_w[31:0], i_valid, i_acc_clr, o_acc[31:0]`
- **A npu_postproc**: `i_clk, i_rstn, i_bias_we, i_bias[31:0], i_go, i_acc[31:0], i_lane[1:0], i_relu_en, i_shift[4:0], i_fc3, o_we, o_wdata[31:0]`
- **B npu_mem_ctrl**: 조원2 파일에서 확인 (주소, 읽기/쓰기 enable, 데이터 포트)
- `npu_ctrl_skeleton.v`: D 포트 예시와 TODO만 적은 틀입니다. 이름은 자유롭게 바꿔도 됩니다.

## 8. 정답(golden v2) 파일
- `golden/mem/`: wmem.hex(가중치), bias.hex(650줄 = FC1 512 + FC2 128 + FC3 10), input_act_a.hex(사진 100장 × 196줄)
- `golden/fc1_out_act_b.hex`: FC1 출력 정답(사진당 128줄) → B의 ACT_A에 들어갈 값 (파일 이름만 다름)
- `golden/fc2_out_act_a196.hex`: FC2 출력 정답(사진당 32줄) → ACT_B
- `golden/fc3_omem.hex`: FC3 점수 정답(사진당 10줄), `labels.txt`: 실제 숫자
- `golden/stages/`: 사진 0~9의 단계별 정답 (1 누산 → 2 +bias → 3 ReLU → 4 shift → 5 포화 → 6 4개 묶음)
- 정확도: int8 99.30% (float 99.32%)

## 9. 11/17까지 해 주실 것
1. `npu_ctrl.v`: 위 for 문 FSM (레이어 설정표 + 타이밍 규칙)
2. `npu_top.v`: A, B, C, D 연결
3. 단위 TB: D 출력 신호(주소, valid, go 등)가 순서대로 나오는지 파형 확인
4. 막히면 단톡에 질문 주세요. 통합 TB는 같이 맞춥니다.
