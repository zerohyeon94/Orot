"""
Mendeley "Annotated Drowsiness Detection Dataset Captured Using Raspberry Pi 5"
(DOI 10.17632/chvz7vh2dc.1, CC BY 4.0)를 학습용 폴더 구조로 정리합니다.

원본은 Edge Impulse 객체 탐지 형식(프레임 + 박스)이므로 Kaggle 데이터와 같은 형태로 맞춥니다.
    - 눈 박스(mata_terbuka/mata_terpejam) → 눈 영역 크롭 → Open/Closed
    - 입 박스(menguap/tidak_menguap)     → 프레임 전체   → yawn/no_yawn

Usage:
    python data/prepare_mendeley.py \
        --modelling_dir "<압축 해제 경로>/modelling" \
        --output ./data/mendeley_raspi5
"""

import argparse
import json
from pathlib import Path

import cv2

EYE_LABELS = {'mata_terbuka': 'Open', 'mata_terpejam': 'Closed'}
MOUTH_LABELS = {'menguap': 'yawn', 'tidak_menguap': 'no_yawn'}
SPLITS = {'training': 'train', 'testing': 'test'}
EYE_MARGIN = 1.4  # Kaggle 눈 이미지처럼 눈썹까지 들어오도록 박스를 넓힘


def crop_square(image, box: dict, scale: float):
    h, w = image.shape[:2]
    cx = box['x'] + box['width'] / 2
    cy = box['y'] + box['height'] / 2
    half = max(box['width'], box['height']) * scale / 2
    x0, y0 = max(int(cx - half), 0), max(int(cy - half), 0)
    x1, y1 = min(int(cx + half), w), min(int(cy + half), h)
    return image[y0:y1, x0:x1]


def prepare(modelling_dir: Path, output: Path) -> dict:
    labels = json.loads((modelling_dir / 'info.labels').read_text())
    counts: dict = {}

    for entry in labels['files']:
        split = SPLITS[entry['category']]
        # zip을 풀면 training/training/<file> 형태가 됨
        src = modelling_dir / entry['category'] / entry['path']
        image = cv2.imread(str(src))
        if image is None:
            raise RuntimeError(f"Failed to load image: {src}")
        stem = Path(entry['name']).stem.replace('.jpg', '')

        eye_idx = 0
        for box in entry['boundingBoxes']:
            label = box['label']
            if label in EYE_LABELS:
                cls, out_img = EYE_LABELS[label], crop_square(image, box, EYE_MARGIN)
                name = f"mendeley_{stem}_eye{eye_idx}.jpg"
                eye_idx += 1
            elif label in MOUTH_LABELS:
                cls, out_img = MOUTH_LABELS[label], image
                name = f"mendeley_{stem}.jpg"
            else:
                continue

            out_dir = output / split / cls
            out_dir.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out_dir / name), out_img)
            counts[(split, cls)] = counts.get((split, cls), 0) + 1

    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description='Prepare Mendeley Raspberry Pi 5 drowsiness dataset')
    parser.add_argument('--modelling_dir', type=str, required=True,
                        help='Extracted "modelling" folder (info.labels, training/, testing/)')
    parser.add_argument('--output', type=str, default='./data/mendeley_raspi5')
    args = parser.parse_args()

    counts = prepare(Path(args.modelling_dir), Path(args.output))
    for (split, cls), n in sorted(counts.items()):
        print(f"{split}/{cls}: {n}")


if __name__ == '__main__':
    main()
