# AUTO_TEST_PLAN.md — 実機・エミュレータ活用と自動テスト計画

利用可能環境: Android実機1台（A202SH）/ Pixel 10 Emulator / (第2実機は不定期接続)
最終更新: 2026-07-04

---

## 能力マトリクス

### 実機でしかできないこと
| 項目 | 理由 |
|---|---|
| BLEアドバタイズ/スキャン実測 | エミュレータはBLE非対応（FGSも権限例外→防御済） |
| すれ違いE2E（2台時のみ） | 電波の相互検出が必要 |
| 通知の実配達（Doze/メーカー省電力） | AQUOS等の実挙動はエミュで再現不可 |
| バッテリー・発熱・実FPS | 物理特性 |
| BLE権限ダイアログの実挙動 | メーカーカスタムUI |

### エミュレータで代替可能なこと
| 項目 | 備考 |
|---|---|
| 全UIレイアウト・テーマ確認 | Pixel 10プロファイルで高解像度確認 |
| オンボーディング/プロフィール初期フロー | クリーンインストールが容易 |
| 永続化テスト（強制終了→再起動） | am force-stop で再現 |
| Supabase通信（認証/解析/同期） | ネットワークは実通信 |
| 画面回転・フォントスケール・言語 | エミュ設定で網羅 |
| ダークモード（システム追従含む） | UIモード切替コマンドで自動化可 |
| ⚠️ 既知問題 | adbがBroken pipeで固まる事象あり→コールドブートで復旧 |

### 自動テスト可能なこと（機械 or AI-in-the-loop）
| レイヤ | 対象 | 手段 | 状態 |
|---|---|---|---|
| 静的 | null/型/未使用 | flutter analyze | 運用中(Gate1) |
| unit | PieceData/DotAvatar/EncounterRecordのJSON往復、PlazaLevel閾値、gateTimeFor境界(0時/18時回帰) | flutter test | **P1で新設** |
| 起動 | クラッシュ即死・FATAL | qa_smoke.sh | 運用中(Gate2) |
| UI巡回 | 7タブスクショ+AI読解 | qa_smoke.sh + QA_GUIDE.md | 運用中(Gate3) |
| golden | 主要Widgetの昼/夜スナップショット | flutter test --update-goldens | P2 |
| 疑似すれ違い | Scannerへのデバッグ注入でBLEなしE2E | kDebugBle拡張 | P4 |

### 手動確認が必要なこと（人間）
- 「気持ちいいか」の最終UX判断（アニメの速度感・音）
- 実世界すれ違いの体験検証（散歩テスト）
- Supabaseダッシュボード操作（DDL/Storage設定）
- デバイスの物理接続・Bluetooth ON

---

## 標準テストレシピ

### R1: 毎サイクル（自動・約3分）
```
pwsh tool/dev.ps1 check && pwsh tool/dev.ps1 build \
  && pwsh tool/dev.ps1 deploy && bash tool/qa_smoke.sh
```

### R2: 永続化回帰（自動・約2分）
```
adb shell am force-stop com.example.ble_encounter
adb shell am start -n com.example.ble_encounter/.MainActivity
# → logs/スクショで カケラ枚数・アイコン・履歴・テーマ設定 が残存すること
```

### R3: 初回体験（エミュ推奨・約5分）
```
adb uninstall com.example.ble_encounter → install → 起動
# → オンボ9ページ→プロフィール→権限2種→ホーム到達をスクショ列で確認
```

### R4: ダーク回帰（自動+AI読解・約4分）
設定→テーマ夜 → qa_smoke.sh → 7枚読解（QA_GUIDE.md ダーク項目）

### R5: BLE実測（実機のみ・2台接続時）
両機起動 → `logcat -s flutter | grep -E "ENCOUNTER|TOKEN|Resolver"` で
1接近1ENCOUNTER・hasProfile=false・resolve成功を確認

---

## P1 unitテスト新設の具体仕様（次セッションでそのまま実装可）

`test/models_test.dart`
- PieceData: toJson→fromJson で256画素一致 / 不正入力で空を返す
- DotAvatar: 16⇔32切替の縮尺 / fill の連結領域限定
- EncounterRecord: toMap→fromMapで全フィールド一致（avatarUrl null含む）

`test/gate_logic_test.dart`（過去バグの回帰固定）
- gateTimeFor(0:30) == 当日9:00（0時バグ）
- gateTimeFor(18:30) == 当日21:00（18時バグ）
- gateTimeFor(21:30) == 翌日9:00 / 境界 8:59/9:00/11:59/12:00/20:59/21:00

`test/plaza_level_test.dart`
- 0→Lv1, 4→Lv1, 5→Lv2, 14→Lv2, 15→Lv3, 49→Lv3, 50→Lv4, 99→Lv4,
  100→Lv5, 249→Lv5, 250→Lv6 / next()の進捗計算
