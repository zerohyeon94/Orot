"""
학습에 쓰지 않은 데이터 폴더로 체크포인트를 평가합니다 (원본 클래스별 정확도 포함).

Usage:
    python training/evaluate.py \
        --checkpoint ./checkpoints/.../best_model.pth ./checkpoints/.../best_model.pth \
        --data_dir ./data/mendeley_raspi5/test
"""

import argparse
import sys
from pathlib import Path

import torch
from torch.utils.data import DataLoader

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from conversion.convert_to_coreml import load_checkpoint
from dataset import DrowsinessDataset, TransformSubset, get_val_transforms


def evaluate(checkpoint: str, dataset: DrowsinessDataset, model_type: str) -> None:
    model = load_checkpoint(checkpoint, model_type).eval()
    loader = DataLoader(
        TransformSubset(dataset, list(range(len(dataset))), get_val_transforms()),
        batch_size=64,
    )
    preds = []
    with torch.no_grad():
        for images, _ in loader:
            outputs = model(images)
            if isinstance(outputs, dict):
                outputs = outputs['drowsiness']
            preds.extend(outputs.argmax(dim=1).tolist())

    per_folder: dict = {}
    for (path, label), pred in zip(dataset.samples, preds):
        hit, total = per_folder.get(path.parent.name, (0, 0))
        per_folder[path.parent.name] = (hit + (pred == label), total + 1)

    correct = sum(h for h, _ in per_folder.values())
    print(f"\n{checkpoint}\n  전체: {correct}/{len(preds)} = {correct / len(preds):.2%}")
    for name, (hit, total) in sorted(per_folder.items()):
        print(f"  - {name:8s}: {hit}/{total} = {hit / total:.2%}")


def main() -> None:
    parser = argparse.ArgumentParser(description='Evaluate checkpoints on a held-out folder')
    parser.add_argument('--checkpoint', type=str, nargs='+', required=True)
    parser.add_argument('--data_dir', type=str, nargs='+', required=True)
    parser.add_argument('--model', type=str, default='default', choices=['default', 'lite'])
    args = parser.parse_args()

    dataset = DrowsinessDataset(root_dir=args.data_dir)
    for checkpoint in args.checkpoint:
        evaluate(checkpoint, dataset, args.model)


if __name__ == '__main__':
    main()
