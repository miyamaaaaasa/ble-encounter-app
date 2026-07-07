#!/usr/bin/env bash
# tool/qa_smoke.sh — 無人スモークQA
# インストール → 起動 → 7タブを比率座標で巡回スクショ → クラッシュ/エラー検出
# 使い方: bash tool/qa_smoke.sh [serial]
# 成果物: qa_out/<serial>/tab_*.png, errors.txt / 終了コード 0=合格 1=要修正
set -u
cd "$(dirname "$0")/.."

SERIAL="${1:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
[ -z "$SERIAL" ] && { echo "NG: no device"; exit 1; }

# adbは接続断でハングしうるため全コマンドにタイムアウトを掛ける
A() { timeout 20 adb -s "$SERIAL" "$@"; }
alive() { [ "$(timeout 5 adb -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" = "device" ]; }
APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="qa_out/$SERIAL"
mkdir -p "$OUT"
echo "== QA smoke on $SERIAL =="

# 1) 最新APKをインストール（存在すれば）
if [ -f "$APK" ]; then
  A install -r "$APK" >/dev/null 2>&1 && echo "installed" || echo "install skipped (signature/err)"
fi

# 1.5) バージョン照合ゲート:
# インストール失敗を見逃して「古いAPKをQAして合格」する事故を防ぐ。
WANT=$(grep -o '^version: [0-9.]*' pubspec.yaml | awk '{print $2}')
GOT=$(A shell dumpsys package com.example.ble_encounter 2>/dev/null \
      | grep -o 'versionName=[0-9.]*' | head -1 | cut -d= -f2)
if [ -n "$WANT" ] && [ "$WANT" != "$GOT" ]; then
  echo "NG: VERSION MISMATCH device=$GOT expected=$WANT"
  echo "    (署名不一致の可能性。adb uninstall 後に再実行してください)"
  exit 1
fi
echo "version on device: $GOT ✓"

# 2) ログをクリアして起動
A logcat -c 2>/dev/null
A shell am force-stop com.example.ble_encounter
A shell am start -n com.example.ble_encounter/.MainActivity >/dev/null
sleep 6

# 3) 解像度から比率座標を計算（GameDock: 下端マージン内の7等分）
SIZE=$(A shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1)
W=${SIZE%x*}; H=${SIZE#*x}
DOCK_Y=$(( H * 90 / 100 ))
TABS=(today plaza game badge kakera self settings)
for i in "${!TABS[@]}"; do
  X=$(( W * (2*i + 1) / 14 ))   # (i+0.5)/7 * W
  alive || { echo "NG: device lost mid-run"; exit 1; }
  A shell input tap "$X" "$DOCK_Y"
  sleep 2
  A exec-out screencap -p > "$OUT/tab_${TABS[$i]}.png" 2>/dev/null
  echo "  shot: tab_${TABS[$i]}.png"
done

# 4) クラッシュ・エラー抽出
A logcat -d 2>/dev/null | grep -E "FATAL EXCEPTION|AndroidRuntime: |flutter : .*(Exception|error|Error)" \
  | grep -v "server unreachable" > "$OUT/errors.txt" || true

# 5) プロセス生存確認（クラッシュ即死検出）
ALIVE=$(A shell pidof com.example.ble_encounter | tr -d '\r')

echo "== result =="
if [ -z "$ALIVE" ]; then
  echo "NG: app process died (crash?)"; cat "$OUT/errors.txt" | tail -20; exit 1
fi
if [ -s "$OUT/errors.txt" ]; then
  echo "WARN: errors captured -> $OUT/errors.txt"; tail -10 "$OUT/errors.txt"; exit 1
fi
echo "OK: alive, no errors. screenshots in $OUT/"
exit 0
