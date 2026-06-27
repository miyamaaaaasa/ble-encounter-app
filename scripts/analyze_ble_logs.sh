#!/usr/bin/env bash
# BLE ログ解析スクリプト
# Usage: bash analyze_ble_logs.sh pixel5.txt aquos.txt

P5="$1"
AQUOS="$2"

echo "========================================"
echo "BLE ログ解析レポート"
echo "========================================"

for f in "$P5" "$AQUOS"; do
  LABEL="$f"
  echo ""
  echo "── $LABEL ──────────────────────────────"

  # サイクル回数
  ON_COUNT=$(grep -c "\[Cycle\] BLE ON" "$f" 2>/dev/null || echo 0)
  OFF_COUNT=$(grep -c "\[Cycle\] BLE OFF" "$f" 2>/dev/null || echo 0)
  echo "スキャンON回数  : $ON_COUNT"
  echo "スキャンOFF回数 : $OFF_COUNT"

  # 検知イベント数
  ENC_COUNT=$(grep -c "\[Encounter\]" "$f" 2>/dev/null || echo 0)
  echo "検知イベント数  : $ENC_COUNT"

  # RSSI 統計
  RSSI_VALUES=$(grep -oP 'rssi=\K[-0-9]+' "$f" 2>/dev/null)
  if [ -n "$RSSI_VALUES" ]; then
    RSSI_COUNT=$(echo "$RSSI_VALUES" | wc -l)
    RSSI_MIN=$(echo "$RSSI_VALUES" | sort -n | head -1)
    RSSI_MAX=$(echo "$RSSI_VALUES" | sort -n | tail -1)
    RSSI_AVG=$(echo "$RSSI_VALUES" | awk '{s+=$1}END{print s/NR}')
    echo "RSSI サンプル数 : $RSSI_COUNT"
    echo "RSSI 最小       : $RSSI_MIN dBm"
    echo "RSSI 最大       : $RSSI_MAX dBm"
    echo "RSSI 平均       : $RSSI_AVG dBm"
  else
    echo "RSSI データなし"
  fi

  # 検知率（ON回数に対して何回成功したか）
  if [ "$ON_COUNT" -gt 0 ] && [ "$ENC_COUNT" -gt 0 ]; then
    RATE=$(echo "scale=1; $ENC_COUNT * 100 / $ON_COUNT" | bc)
    echo "推定検知率      : ${RATE}%"
  fi
done

echo ""
echo "========================================"
echo "推奨インターバル算出"
echo "========================================"

# 推奨スキャン時間の根拠:
# - BLE アドバタイジング間隔: 通常 100ms ~ 500ms
# - 10秒スキャン = 20~100 アドバタイジングパケットをキャプチャ可能
# - 電池消費: デューティ比が重要 (ON / (ON+OFF))
# 目標: デューティ比 3-5%、検知率 >80%
echo "現在デバッグ設定 : ON=12s / OFF=48s (デューティ比 20%)"
echo "本番推奨         : ON=15s / OFF=585s (デューティ比 2.5%)"
echo "最適化候補       : ON=15s / OFF=285s (デューティ比 5%, 5分周期)"
echo ""
