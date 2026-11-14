C 블록 npu_pe_array (조원3) - 통합용 정리본 (11/12)

파일
  npu_pe_array.v  : 설계 (Design Sources)
  tb_pe_array.v   : 단위 TB (Simulation Sources), 사진 0 FC1/FC2/FC3 golden 비교 -> PASS
  hex/            : TB용 데이터 (wmem, 사진 0 입력, FC1/FC2 출력, 정답 acc)

포트
  clk, rstn(active-low)
  i_x[31:0]   int8 x 4 입력      <- B (IMEM/ACT)
  i_w[31:0]   int8 x 4 가중치    <- B (WMEM)
  i_valid     데이터 유효        <- D (통합 TB에서는 TB가 줌)
  i_acc_clr   누산기 0으로       <- D
  o_acc[31:0] s32 누산 결과 (bias 전) -> A 의 acc 입력

통합 시 지켜야 할 타이밍
  1) 뉴런 시작 전 i_acc_clr 1클럭
  2) i_valid = 1 로 L클럭 (FC1 196 / FC2 128 / FC3 32)
     * B의 BRAM 읽기 지연(보통 1클럭)만큼 i_valid도 늦춰서 데이터와 맞출 것
  3) 마지막 valid 클럭 + 2클럭 뒤 o_acc 가 최종값 -> 이때 A에 넘기기
  lane0 = [7:0] ... lane3 = [31:24], x와 w의 lane 순서가 같아야 함

디버깅: sw/golden_team/golden/pe_trace/ 에 사진 0 전 뉴런 클럭별 p0~p3, 트리합, acc 정답
