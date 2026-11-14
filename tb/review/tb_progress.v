`timescale 1ns / 1ps
// ============================================================================
// tb_progress : 느린 넷리스트 시뮬레이션용 진행 표시 (테스트벤치 전용)
//   tb_npu_top 옆에 "두 번째 top" 으로 같이 올리면 1만 클럭마다 한 줄, busy/done 이 바뀔 때마다 한 줄을 찍음.
//   타이밍 시뮬은 사진 1장에 수십 분이 걸려서, 멈춘 건지 도는 중인지 보려고 만듦.
//   xelab ... work.tb_npu_top work.tb_progress work.glbl
// ============================================================================
module tb_progress;
    integer cyc;
    initial cyc = 0;
    always @(posedge tb_npu_top.i_clk) begin
        cyc = cyc + 1;
        if (cyc % 10000 == 0)
            $display("[T] %0d clocks  busy=%b done=%b dout=%h", cyc, tb_npu_top.o_busy, tb_npu_top.o_done, tb_npu_top.o_dout);
    end
    always @(tb_npu_top.o_busy) $display("[T] o_busy -> %b at %0t", tb_npu_top.o_busy, $time);
    always @(tb_npu_top.o_done) $display("[T] o_done -> %b at %0t", tb_npu_top.o_done, $time);
endmodule
