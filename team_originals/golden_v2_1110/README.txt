골든 모델 v2 (11/10) - shift 를 학습셋 기준으로 고른 버전

결과: FP32 99.32% -> 정수 99.30%, shift FC1 = 11, FC2 = 7 (학습 이미지 1만 장 정확도 기준 선택)
v1 과의 차이: v1 은 shift 를 테스트셋 기준으로 골라서 10 / 9, 99.32%.
  테스트셋은 마지막 측정에만 써야 하므로 v2 가 공정한 값.
  weight.hex, input_*.hex 는 v1 과 똑같음.
  bias.hex 는 FC1(0~511) 같음, FC2(512~639)·FC3(640~649) 바뀜.
  golden_fc1/fc2/fc3_*.hex 전부 바뀜.
하드웨어 영향: D 레이어 설정표 shift 를 FC1 11, FC2 7 로. A·B·C RTL 변경 없음.

파일 (v1 과 형식 동일)
  golden_v1.py   모델(mlp_mnist.pt) -> 정수화 -> 정확도 -> hex 생성 (--select train 으로 실행)
  check_hex.py   hex 만 읽어 하드웨어 순서로 재계산, golden 과 비트 비교
  out/weight.hex, out/bias.hex, out/input_XXXX.hex, out/golden_fc1/2/3_XXXX.hex
  out/labels.txt, out/debug_0000.txt, out/summary.txt
  out/stages/    A 블록 단위 테스트용 단계별 정답 (이미지 0, gen_stages.py --s1 11 --s2 7)

다시 만들기
  python golden_v1.py --model mlp_mnist.pt --mnist ./mnist --out ./out --n_images 10 --select train
  python check_hex.py --dir ./out --img 0 --s1 11 --s2 7
