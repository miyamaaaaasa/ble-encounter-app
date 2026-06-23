// BLE 動作設定
// kDebugBle = true  → 高頻度スキャン・ゲート常時開放（実機テスト用）
// kDebugBle = false → 本番設定（実機ログ解析で最適化済み）
const bool kDebugBle = false;

// スキャンサイクル (秒)
// 実機ログ根拠: 検知レイテンシ 70-160ms → 15s 以上で十分
// 2分サイクル = 5分近接で51%検知 (旧10分サイクルは26%)
// バッテリー影響: デューティ比 6.25% → 0.1%/日 未満の増加（無視可）
const int kScanOnSeconds  = kDebugBle ? 12 : 15;
const int kScanOffSeconds = kDebugBle ? 48 : 105; // 本番: 2分周期に最適化

// ゲート制御
const bool kGateAlwaysOpen = kDebugBle; // デバッグ時は常時開放
