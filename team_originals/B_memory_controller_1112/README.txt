NPU MEMORY CONTROLLER - 전달 및 통합 안내
==========================================

1. 개요
-------
본 파일은 NPU 프로젝트의 메모리 컨트롤러 RTL, Vivado Block Memory Generator IP,
메모리 초기화 데이터 및 기능 검증용 테스트벤치를 팀원에게 전달하기 위한 안내서입니다.

설계 대상: AMD/Xilinx Kria K26 SOM (xck26)
개발 환경: Vivado 2024.1

현재 상태:
- 메모리 컨트롤러 기본 RTL 및 BRAM IP 구성 완료
- Vivado Behavioral Simulation에서 독립 기능 테스트 통과
- Synthesis/BRAM 사용량/타이밍 검증은 미완료 (Vivado 강제 종료 문제)
- 전체 NPU(FSM/PE) 통합 및 end-to-end 추론 검증은 미완료

2. 전달 파일
-----------
NPU_Memory_Delivery/
  memory_controller.v       : 합성 대상 메모리 컨트롤러
  memory_controller_tb.v    : 시뮬레이션 테스트벤치 (합성 대상 아님)
  ip/                       : BRAM IP 정의(.xci) 10개
  hex/                      : 초기화 및 시뮬레이션 데이터(.coe/.hex)
  README.txt                : 본 안내서

IP 목록 (총 10개):
  wmem_bank0.xci
  wmem_bank1.xci
  wmem_bank2.xci
  wmem_bank3.xci
  bmem_128.xci
  imem_a_bram.xci
  imem_b_bram.xci
  act_a_bram.xci
  act_b_bram.xci
  omem_bram.xci

주요 초기화 파일:
  hex/weight_bank0.coe ~ weight_bank3.coe : WMEM 4개 뱅크 초기화
  hex/bias_128bit.coe                     : BMEM 초기화
  hex/bias_128bit.hex                     : BMEM 시뮬레이션 기대값
  hex/input_0000.hex                      : MNIST 입력 데이터

기존 weight.coe, weight.hex, bias 관련 파일은 테스트벤치/기존 데이터 참조
가능성을 고려해 함께 전달합니다. 실제 사용 여부는 소스 코드에서 확인하세요.

3. 메모리 구조
-------------
- WMEM: 4개 뱅크, 각 32bit x 29,280 words
  각 뱅크는 PE별 가중치를 병렬 출력합니다.
  공통 weight_addr(15bit), weight_req; 출력 weight_data0~3(각 32bit), weight_valid
- BMEM: 128bit x 163 words
  한 워드에 32bit bias 4개를 패킹합니다.
  [31:0]=Bias0, [63:32]=Bias1, [95:64]=Bias2, [127:96]=Bias3
  bias_addr(8bit), bias_req, bias_data(128bit), bias_valid
- IMEM_A/B: 각 32bit x 196 words
- ACT_A: 32bit x 128 words
- ACT_B: 32bit x 32 words
- OMEM: 32bit x 10 words

정확한 입출력 포트 및 동작 타이밍은 memory_controller.v를 기준으로 확인하세요.

4. Vivado 프로젝트에 추가하기
---------------------------
(1) Vivado 2024.1에서 팀 프로젝트를 엽니다.
(2) Add Sources > Add or Create Design Sources로 memory_controller.v를 추가합니다.
(3) Add Sources > Add or Create Simulation Sources로 memory_controller_tb.v를 추가합니다.
(4) Add Sources에서 ip/의 .xci 파일 10개를 프로젝트에 추가합니다.
    기존 프로젝트에 동일 이름 IP가 있으면 중복 생성하지 말고 충돌 여부를 확인하세요.
(5) 각 IP의 Block Memory Generator 설정에서 초기화 COE 파일 경로를 확인합니다.
    WMEM: weight_bank0.coe ~ weight_bank3.coe
    BMEM: bias_128bit.coe
    초기화가 필요한 다른 IP가 있다면 해당 설정도 확인합니다.
(6) IP Sources에서 필요한 IP를 선택하여 Generate Output Products를 실행합니다.
(7) 시뮬레이션 전에 테스트벤치의 $readmemh 경로를 팀원 PC 환경에 맞게 수정합니다.
    원본 테스트벤치에는 D:/NPU_MEMORY/hex/... 형태의 절대경로가 있을 수 있습니다.
(8) Run Behavioral Simulation을 실행하여 검증합니다.

주의: .xci만 복사해도 COE 파일 경로가 자동으로 새 PC에 맞춰지는 것은 아닙니다.
     IP 초기화 경로와 $readmemh 경로를 반드시 점검하세요.

5. 검증 결과
-----------
독립 메모리 컨트롤러 테스트벤치에서 다음 항목을 확인했습니다.
- WMEM 4-Bank 읽기: 4/4 PASS
- WMEM FC1 순차 읽기: 784/784 PASS
- WMEM 경계 읽기: 32/32 PASS
- WMEM 연속 읽기 및 valid 동작: PASS
- BMEM 128bit 데이터: PASS
- BMEM 전체 읽기: 163/163 PASS
- BMEM 연속 읽기 및 valid 동작: PASS
- MNIST 입력 적재/읽기: 196/196 PASS
- Reset 후 valid 신호 초기화: PASS

최종 시뮬레이션 메시지:
  MEMORY CONTROLLER 4-BANK ALL TESTS PASSED

테스트벤치의 기존 시뮬레이션 실행 시간은 20 us로 설정하여 전체 테스트를
완료했습니다. 새 프로젝트에서는 시뮬레이션 실행 시간을 충분히 설정하세요.

6. 팀 통합 시 확인 사항
--------------------
- FSM에서 메모리 주소, 요청 신호 및 읽기 데이터의 valid 타이밍 확인
- PE 4개에 WMEM 4개 뱅크의 데이터가 올바르게 매핑되는지 확인
- BMEM 128bit 데이터의 Bias0~3 분리 순서 확인
- 메모리 읽기 지연을 반영한 제어 타이밍 확인
- 골든 모델과 전체 NPU 출력 비교
- Synthesis 완료 후 BRAM 사용량과 타이밍 확인

7. 알려진 제한 사항
-----------------
- 현재 Vivado에서 Synthesis 실행 도중 강제 종료 현상이 발생하여 합성 성공 여부,
  실제 FPGA 자원 사용량 및 타이밍 만족 여부를 확인하지 못했습니다.
- Behavioral Simulation 통과는 실제 FPGA 구현 성공을 보장하지 않습니다.
- 테스트벤치의 절대경로 및 IP의 COE 경로를 팀원 PC에서 수정해야 할 수 있습니다.

작성 기준: 2026-11-12
