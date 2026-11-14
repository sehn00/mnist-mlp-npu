// ============================================================================
// probe.v : XSim 이 SDF 의 클럭 배선 지연(INTERCONNECT)을 어떤 플립플롭에 적용하는지 보는 최소 실험
//   FDCE 4개가 같은 클럭(BUFGCE 출력)을 받는다. SDF(probe.sdf)에는 네 개 모두 클럭 배선 지연 2000 ps.
//     \a_reg[0]  : 이름에 대괄호,  하위 모듈 안
//     b_reg      : 대괄호 없음,    하위 모듈 안
//     \c_reg[0]  : 이름에 대괄호,  top 에 직접
//     d_reg      : 대괄호 없음,    top 에 직접
//   지연이 다 적용되면 네 출력이 같은 시각(클럭 엣지 + 2000 + C->Q)에 바뀌어야 한다.
// 실행: scripts/review/sdf_probe.sh   (결과는 reports/review/sdf_probe.txt)
// ============================================================================
`timescale 1 ps / 1 ps
module probe_sub (input CLK, input D, output Q0, output Q1);
    FDCE #(.INIT(1'b0)) \a_reg[0] (.C(CLK), .CE(1'b1), .CLR(1'b0), .D(D), .Q(Q0));
    FDCE #(.INIT(1'b0)) b_reg      (.C(CLK), .CE(1'b1), .CLR(1'b0), .D(D), .Q(Q1));
endmodule

module probe_top (input clk, input d, output q0, output q1, output q2, output q3);
    wire c;
`ifndef NO_ANNO
initial begin
 $sdf_annotate("probe.sdf",,,,"tool_control");
end
`endif
    BUFGCE bg (.I(clk), .CE(1'b1), .O(c));
    probe_sub u_s (.CLK(c), .D(d), .Q0(q0), .Q1(q1));
    FDCE #(.INIT(1'b0)) \c_reg[0] (.C(c), .CE(1'b1), .CLR(1'b0), .D(d), .Q(q2));
    FDCE #(.INIT(1'b0)) d_reg      (.C(c), .CE(1'b1), .CLR(1'b0), .D(d), .Q(q3));
endmodule

`timescale 1 ns / 1 ps
module probe_tb;
    reg  clk = 1'b0, d = 1'b0;
    wire q0, q1, q2, q3;
    probe_top u (.clk(clk), .d(d), .q0(q0), .q1(q1), .q2(q2), .q3(q3));
    always #5 clk = ~clk;                       // 상승 엣지: 5, 15, 25, ... ns
    initial begin
        #200 d = 1'b1;                          // 205 ns 엣지에서 잡혀야 함 (GSR 은 100 ns 까지)
        #40 $finish;
    end
    always @(q0) $display("q0 (sub, bracket name)  = %b at %0.3f ns  (clock edge %+0.3f ns)", q0, $realtime, $realtime - 205.0);
    always @(q1) $display("q1 (sub, plain name)    = %b at %0.3f ns  (clock edge %+0.3f ns)", q1, $realtime, $realtime - 205.0);
    always @(q2) $display("q2 (top, bracket name)  = %b at %0.3f ns  (clock edge %+0.3f ns)", q2, $realtime, $realtime - 205.0);
    always @(q3) $display("q3 (top, plain name)    = %b at %0.3f ns  (clock edge %+0.3f ns)", q3, $realtime, $realtime - 205.0);
endmodule
