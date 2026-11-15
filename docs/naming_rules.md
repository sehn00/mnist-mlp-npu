# 이름 통일 규칙 (팀 공통) · 2026-11-12

통합할 때 이름이 달라서 연결이 꼬이지 않게, 모든 .v 파일은 아래 규칙을 따릅니다.

## 1. 포트 이름
| 종류 | 규칙 | 예 |
|---|---|---|
| 클럭 | `i_clk` | |
| 리셋 | `i_rstn` (0이면 리셋, 비동기) | `always @(posedge i_clk or negedge i_rstn)` |
| 입력 | `i_` + 이름 | `i_x`, `i_valid` |
| 출력 | `o_` + 이름 | `o_acc`, `o_we` |
| 내부 레지스터 | `r_` + 이름 | `r_bias`, `r_pack` |
| 내부 조합 선 | `w_` + 이름 | `w_sum`, `w_relu` |
| 모듈 안 인스턴스 | `u_` + 블록 | `u_A`, `u_B`, `u_C`, `u_D` |

- 클럭은 100 MHz 하나만 씁니다.
- 숫자 상수는 비트 수를 붙입니다: `32'sd0`, `1'b1`

## 2. 모듈 / 파일 이름
| 블록 | 모듈 = 파일 이름 | 담당 |
|---|---|---|
| A | `npu_postproc` / npu_postproc.v | 조원1 |
| B | `npu_mem_ctrl` / npu_mem_ctrl.v | 조원2 |
| C | `npu_pe_array` / npu_pe_array.v | 조원3 |
| D | `npu_ctrl` / npu_ctrl.v | 조원4 |
| 최상위 | `npu_top` / npu_top.v | 조원4 |
| TB | `tb_` + 모듈 이름 (`tb_npu_top.v`) | |

## 3. npu_top 안의 연결 선 이름 (블록 사이 wire)
선 이름 = **보내는 블록 출력 이름에서 `o_`를 뺀 것**. 받는 블록 입력에 그대로 꽂습니다.

| 선 이름 | 비트 | 보내는 쪽 | 받는 쪽 |
|---|---|---|---|
| `x` | 32 | B (입력/ACT 메모리 읽기 데이터) | C `i_x` |
| `w` | 32 | B (WMEM 읽기 데이터) | C `i_w` |
| `bias` | 32 | B (BMEM 읽기 데이터) | A `i_bias` |
| `acc` | 32 | C `o_acc` | A `i_acc` |
| `we` | 1 | A `o_we` | B (출력 메모리 쓰기 enable) |
| `wdata` | 32 | A `o_wdata` | B (출력 메모리 쓰기 데이터) |
| `valid` | 1 | D `o_valid` | C `i_valid` |
| `acc_clr` | 1 | D `o_acc_clr` | C `i_acc_clr` |
| `bias_we` | 1 | D `o_bias_we` | A `i_bias_we` |
| `go` | 1 | D `o_go` | A `i_go` |
| `lane` | 2 | D `o_lane` | A `i_lane` |
| `relu_en` | 1 | D `o_relu_en` | A `i_relu_en` |
| `shift` | 5 | D `o_shift` | A `i_shift` |
| `fc3` | 1 | D `o_fc3` | A `i_fc3` |
| `waddr` | 17 | D `o_waddr` | B (WMEM 주소) |
| `xaddr` | 8 | D `o_xaddr` | B (입력/ACT 주소) |
| `baddr` | 10 | D `o_baddr` | B (BMEM 주소) |
| `oaddr` | 8 | D `o_oaddr` | B (출력 메모리 주소) |
| `layer` | 2 | D `o_layer` | B (0 FC1, 1 FC2, 2 FC3: 어느 메모리를 읽고 쓸지) |

- B 포트 이름은 조원2 파일이 기준입니다. B 쪽 이름이 다르면 **B 이름을 이 표에 맞추거나**, 표를 B에 맞춰 고친 뒤 단톡에 공유합니다.
- D 포트(`o_valid` 등)는 npu_ctrl_skeleton.v 예시 기준이고, 조원4가 바꾸면 이 표도 같이 고칩니다.

## 4. 연결 예시 (npu_top.v 일부)
```verilog
wire [31:0] x, w, acc;
wire        valid, acc_clr;

npu_pe_array u_C (
    .i_clk(i_clk), .i_rstn(i_rstn),
    .i_x(x), .i_w(w), .i_valid(valid), .i_acc_clr(acc_clr),
    .o_acc(acc)
);
npu_postproc u_A (
    .i_clk(i_clk), .i_rstn(i_rstn),
    .i_bias_we(bias_we), .i_bias(bias), .i_go(go), .i_acc(acc),
    .i_lane(lane), .i_relu_en(relu_en), .i_shift(shift), .i_fc3(fc3),
    .o_we(we), .o_wdata(wdata)
);
```

## 5. 현재 상태
- A ✓ 규칙 맞음 / C ✓ 11/12에 clk, rstn → i_clk, i_rstn 으로 수정 (PASS 재확인)
- B ? 조원2 파일 확인 필요 / D: 틀(skeleton)은 규칙 맞음
