#!/usr/bin/env python3
"""tool/qa_diff.py — スクリーンショット差分QA (Phase3)

qa_smoke.sh が撮った qa_out/<serial>/tab_*.png を
ベースライン qa_baseline/<serial>/ と比較し、変化率を報告する。

使い方:
  python tool/qa_diff.py <serial>            # 差分比較
  python tool/qa_diff.py <serial> --update   # 現在のスクショをベースライン化

判定:
  変化率 < 1%  : OK（時計・カウントダウン等の微小変化）
  1% - 15%     : REVIEW（AIがスクショを読解して判断）
  > 15%        : ALERT（レイアウト崩れ/テーマ破綻/画面消失の可能性大）

意図的なUI変更をしたら --update でベースラインを更新すること。
終了コード: 0=全OK / 2=REVIEWあり / 3=ALERTあり / 1=実行エラー
"""
import sys
import shutil
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # cp932コンソール対策

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
OK_TH, ALERT_TH = 0.01, 0.15


def diff_ratio(a: Path, b: Path) -> float:
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return 1.0  # 解像度が違えば全変化扱い
    # 差分の平均輝度 / 255 を「変化率」とする（軽量・十分実用的）
    d = ImageChops.difference(ia, ib)
    hist = d.histogram()
    total = sum(hist[i % 256] * (i % 256) for i in range(len(hist)))
    return total / (ia.size[0] * ia.size[1] * 3 * 255)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    serial = sys.argv[1]
    update = "--update" in sys.argv
    cur = ROOT / "qa_out" / serial
    base = ROOT / "qa_baseline" / serial

    if not cur.exists():
        print(f"NG: {cur} がない。先に tool/qa_smoke.sh を実行")
        return 1

    if update:
        base.mkdir(parents=True, exist_ok=True)
        for p in cur.glob("tab_*.png"):
            shutil.copy2(p, base / p.name)
        print(f"baseline updated: {base}")
        return 0

    if not base.exists():
        print("baseline なし → 初回として自動作成")
        base.mkdir(parents=True, exist_ok=True)
        for p in cur.glob("tab_*.png"):
            shutil.copy2(p, base / p.name)
        return 0

    worst = 0
    print(f"== screenshot diff: {serial} ==")
    for p in sorted(cur.glob("tab_*.png")):
        bp = base / p.name
        if not bp.exists():
            print(f"  NEW    {p.name} (ベースラインに存在しない)")
            worst = max(worst, 2)
            continue
        r = diff_ratio(bp, p)
        if r < OK_TH:
            mark, lv = "OK    ", 0
        elif r < ALERT_TH:
            mark, lv = "REVIEW", 2
        else:
            mark, lv = "ALERT ", 3
        worst = max(worst, lv)
        print(f"  {mark} {p.name}  変化率 {r*100:.2f}%")
    # ベースラインにあって今回無い＝画面が撮れていない
    for bp in sorted(base.glob("tab_*.png")):
        if not (cur / bp.name).exists():
            print(f"  MISSING {bp.name} (今回撮影されていない)")
            worst = max(worst, 3)

    print({0: "== ALL OK ==", 2: "== REVIEW required: AIがスクショを読解すること ==",
           3: "== ALERT: レイアウト崩れの可能性。即確認 =="}[worst])
    return worst


if __name__ == "__main__":
    sys.exit(main())
