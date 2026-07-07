# PREFECTURE_PLAN.md — 47都道府県コンテンツ管理設計（Phase9）

将来の「特産品・図鑑・カケラ・パズル」に備えたデータ構造。
方針: **コードとコンテンツを分離**し、コンテンツ追加でDartを書かなくて済む形にする。

最終更新: 2026-07-04

---

## 1. 既存の前提

- 都道府県コードは既に全域で `0..46`（北海道=0 … 沖縄=46）で統一済み
  （OwnProfile.prefecture / EncounterRecord.prefecture / -1=未設定）
- 名称リストが today_screen / profile_screen に**重複ハードコード**されている
  → 本計画で一元化する（重複排除は移行タスク1）

## 2. データ構造

### 2.1 マスタ（コード内・軽量）
`lib/data/prefectures.dart`
```dart
class Prefecture {
  final int id;            // 0-46（既存コードと互換）
  final String name;       // '北海道'
  final String region;     // '北海道','東北','関東','中部','近畿','中国','四国','九州・沖縄'
  const Prefecture(this.id, this.name, this.region);
}
const prefectures = <Prefecture>[ /* 47件 */ ];
```

### 2.2 コンテンツ（JSONアセット・拡張はここだけ）
`assets/prefectures/<id>_<romaji>.json`（例: `12_tokyo.json`）
```json
{
  "id": 12,
  "specialties": [
    {
      "key": "monja",
      "name": "もんじゃ焼き",
      "icon": "assets/prefectures/icons/12_monja.png",
      "rarity": 1,
      "flavor": "鉄板の上のお祭りだ！"
    }
  ],
  "puzzle": {
    "art": "assets/puzzle/pref_12.png",
    "pieces": 12
  },
  "fish": { "name": "江戸前アナゴ", "icon": "..." }
}
```
- ロード: `PrefectureContent.load(id)`（rootBundle+キャッシュ）。JSON不在なら空を返し
  アプリは絵なしで動く（**段階的にコンテンツを足せる**）
- 検証: tool/asset_audit.py がJSON内のiconパス実在まで検査するよう拡張（P1）

### 2.3 収集状態（端末側・小さく保つ）
SharedPreferences `pref_collection_v1`:
```json
{ "12": { "monja": {"n": 3, "first": "2026-07-04"} } }
```
- 保存は「key→取得数と初取得日」だけ。名前や画像はマスタ参照（重複保存しない）
- Supabase同期はしない（コレクションは端末の思い出。DB使用量も守る）

## 3. 遊びへの接続

| 機能 | 仕組み |
|---|---|
| 特産品ドロップ | 開門時、相手の prefecture の specialties から抽選（rarity重み） |
| 図鑑 | region×prefecture のグリッド。未取得はシルエット表示 |
| 地域制覇バッジ | region内の全prefectureで1つ以上取得→バッジ（badge_screenの準備UIと接続） |
| ご当地パズル | pref_XX.png を PieceData 形式に分割配布 |
| 水族館 | fish フィールドを AquariumScreen が参照（現行ハードコードを置換） |

プライバシー注意: 特産品は「相手の出身地設定」由来であり位置情報ではない。
未設定(-1)の相手からは「どこかのおみやげ」（汎用アイテム）を出す。

## 4. 移行タスク

1. 名称リスト一元化（today/profile の重複配列 → prefectures.dart 参照）※既存表示に影響なし
2. `assets/prefectures/` 雛形（README + 東京のサンプルJSON1件）
3. asset_audit のJSON検査拡張
4. 特産品ドロップMVP（開門演出に1行足すだけの規模）
