`timescale 1ns / 1ps
// ============================================================================
// tb_dump : 넷리스트 시뮬레이션 비교용 파형 덤프 (테스트벤치 전용)
//   tb_npu_top 옆에 "두 번째 top" 으로 올리면 npu_top 과 블록 4개(+ 메모리 래퍼)의 신호를
//   DUMP_NS 나노초 동안 dump.vcd 로 남기고 시뮬레이션을 끝냄.
//   같은 넷리스트를 지연 없이 / SDF 지연을 넣고 각각 돌린 뒤 scripts/review/vcd_compare.py 로
//   "몇 번째 클럭에 어느 신호부터 달라지는지" 찾는 데 씀.
// ============================================================================
`ifndef DUMP_NS
  `define DUMP_NS 12500
`endif
module tb_dump;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(1, tb_npu_top.u_top);
        $dumpvars(1, tb_npu_top.u_top.u_D);
        $dumpvars(1, tb_npu_top.u_top.u_C);
        $dumpvars(1, tb_npu_top.u_top.u_A);
        $dumpvars(1, tb_npu_top.u_top.u_B);
        $dumpvars(1, tb_npu_top.u_top.u_B.u_mem);
        #(`DUMP_NS) $finish;
    end
endmodule
