# 보관: 출력 레지스터 ON 구성 결과 (2026-11-14, 커밋 0ae9085 기준)

WMEM/BMEM 출력 레지스터 ON, RD_LAT=2 구성으로 돌린 결과. 과제 가이드 p.9("Primitives Output Register should be disabled") 위반이라 폐기된 구성이고, OFF 구성과 비교하려고 남겨 둠.

- result.txt, sim_100img.txt: 시뮬레이션 (100장 일치, 장당 119,659클럭)
- result_impl.txt, impl_summary.txt, synth_*.rpt, impl_*.rpt: 합성 + 구현 (WNS +2.138 ns, WHS +0.041 ns)
