#!/usr/bin/env python3
"""tool/asset_audit.py — アセット監査 (Phase8)

1. コードが参照する 'assets/...' パスの実在チェック（欠損検出）
2. ディスク上のアセットのうちコード未参照のもの（未使用検出）
3. pubspec.yaml 宣言との整合（フォルダ構成監査）

終了コード: 0=問題なし / 1=欠損あり（ビルドは通るが実行時に絵が出ない）
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # cp932コンソール対策

ROOT = Path(__file__).resolve().parent.parent
EXPECTED_DIRS = ["icons", "gate", "doticons", "puzzle", "prefectures", "rpg"]


def main() -> int:
    # 1) コード参照の収集
    refs: dict[str, list[str]] = {}
    for f in (ROOT / "lib").rglob("*.dart"):
        for m in re.finditer(r"['\"](assets/[^'\"]+)['\"]", f.read_text(encoding="utf-8")):
            refs.setdefault(m.group(1), []).append(str(f.relative_to(ROOT)))

    # 2) ディスク上の実ファイル
    disk = set()
    adir = ROOT / "assets"
    if adir.exists():
        for p in adir.rglob("*"):
            if p.is_file():
                disk.add(p.relative_to(ROOT).as_posix())

    # 3) pubspec 宣言
    pub = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    declared = re.findall(r"^\s+-\s+(assets/[^\s]+)\s*$", pub, re.M)

    missing = sorted(r for r in refs if r not in disk)
    unused = sorted(d for d in disk if d not in refs
                    and not any(d.startswith(x.rstrip("/") + "/") is False for x in [])  # keep simple
                    )
    unused = sorted(d for d in disk if d not in refs)
    undeclared_dirs = sorted({Path(d).parent.as_posix() + "/" for d in disk}
                             - {x if x.endswith("/") else x + "/" for x in declared})

    print("== asset audit ==")
    print(f"参照: {len(refs)}件 / 実ファイル: {len(disk)}件 / pubspec宣言: {declared}")

    print("\n-- 欠損（コードが参照するが存在しない）--")
    if missing:
        for r in missing:
            print(f"  MISSING {r}  <- {refs[r][0]}")
    else:
        print("  なし ✓")

    print("\n-- 未使用（存在するがコード未参照）--")
    if unused:
        for d in unused:
            print(f"  UNUSED  {d}")
    else:
        print("  なし ✓")

    print("\n-- pubspec未宣言フォルダ --")
    if undeclared_dirs:
        for d in undeclared_dirs:
            print(f"  UNDECLARED {d}")
    else:
        print("  なし ✓")

    print("\n-- 将来フォルダの準備状況 --")
    for d in EXPECTED_DIRS:
        mark = "✓" if (adir / d).exists() else "（未作成・将来用）"
        print(f"  assets/{d}/ {mark}")

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
