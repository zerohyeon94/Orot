# Mendeley Raspberry Pi 5 Drowsiness Dataset (정리본)

- 원본: Isworo, N. et al., "Annotated Drowsiness Detection Dataset Captured Using Raspberry Pi 5", Mendeley Data, V1, 2025. https://doi.org/10.17632/chvz7vh2dc.1
- 라이선스: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)
- 변경 사항: 원본 `modelling/` 분할의 객체 탐지 박스를 사용해 눈 박스는 크롭하여 `Open`/`Closed`로, 입 박스 라벨은 프레임 전체를 `yawn`/`no_yawn`으로 재분류했습니다. 생성 스크립트: `data/prepare_mendeley.py`
- `train/`은 학습에, `test/`는 외부 평가(`training/evaluate.py`)에만 사용합니다.
