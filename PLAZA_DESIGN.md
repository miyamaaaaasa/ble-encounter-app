# PLAZA_DESIGN.md — 広場育成システム設計書（Phase7）

現状分析と、将来機能（ドット絵住民・広場レベル・背景進化・おしゃべり演出）の
拡張設計。実装の半分は v1.7.5 で稼働済み。本書は「次に足すもの」を定義する。

最終更新: 2026-07-04

---

## 1. 現状（v1.7.5 実装済み）

| 要素 | 実装 | 場所 |
|---|---|---|
| 住民表示 | 最近8人・前後2列・ID由来の固定位置 | `PlazaScene`（lib/ui/widgets/plaza_scene.dart） |
| ぷるぷる待機 | 位相ずらし正弦波（1コントローラ共有） | 同上 |
| 向き変更 | IDハッシュで左右（画像のみ反転） | 同上 |
| おしゃべり | 3.5〜6秒毎にランダム1人が2.6秒吹き出し | 同上 |
| 広場レベル | Lv1〜6・閾値0/5/15/50/100/250（回帰テスト済） | `PlazaLevel` |
| 背景進化 | CustomPaint（木→花→ベンチ→提灯、夜は星空） | `_PlazaBgPainter` |

## 2. アーキテクチャ方針

```
appProvider(encounters) ──┐
puzzleProvider(pieces) ───┼─→ PlazaScene（表示は状態から純粋に導出）
[新] plazaEventProvider ──┘     ↑ 演出イベント（登場/発見）だけを流す
```
- 演出は**イベント駆動**にする: `PlazaEvent { newResident(peerId) | kakeraFound(peerId) }`
  を `StateProvider<PlazaEvent?>` で配信し、PlazaSceneが消費してアニメ再生
- 発火元: `AppNotifier.upsertFromServerProfile`（新規時）/ `PuzzleNotifier.resolvePending`
- 世界観制約: 演出はすべて**開門後のみ**（気配段階では絶対に住民を出さない）

## 3. 新規住民「歩いて登場」演出（次実装・工数S）

1. resolve完了で `PlazaEvent.newResident(id)` 発火
2. PlazaScene: 該当住民を画面右外 `x=W+60` に生成
3. 800ms かけて定位置へ `Curves.easeOutCubic` で歩行（上下2pxの歩きバウンス）
4. 到着時に ✨パーティクル（既存の祝福ポップ流用）＋ 吹き出し「はじめまして！」
5. 以後は通常の待機ループへ合流

## 4. カケラ発見演出（工数S）

- 新カケラ入手時、対応住民の頭上に 💎 が浮かんで3回バウンス
- タップで カケラタブへジャンプ（`homeTabProvider` を新設しタブ切替を公開）

## 5. 住民の記憶・性格（工数M・v1.9候補）

`ResidentPersona`（peerIdハッシュから決定論的に生成、保存不要）:
- 歩く速さ / おしゃべり頻度 / 好きな場所（花壇寄り・ベンチ寄り）
- 再会回数(meetCount)が増えると: 手を振る頻度UP → 常連は自分の近くに立つ
- **匿名性維持**: ペルソナは見た目の揺らぎのみ。個人特定要素は一切持たせない

## 6. 背景アセット差し替え計画（CustomPaint→ドット絵）

```
assets/plaza/
  bg_lv1.png 〜 bg_lv6.png   # 960×540 昼版（夜はコードでトーン変換＋星/提灯重畳）
  deco_tree.png / deco_flower.png / deco_bench.png / deco_lantern.png  # 64×64
```
- 実装: `_PlazaBgPainter` を `Image.asset(bg_lv$n)` + デコ配置レイヤに置換
- アセット未配置の間は現CustomPaintがフォールバック（両立可能な設計にする）
- 監査: tool/asset_audit.py が assets/plaza/ を将来フォルダとして追跡済み

## 7. レベルアップ演出（工数S）

- PlazaLevel が上がった瞬間: 画面フラッシュ→新レベル名を看板ドロップ表示
  「🎊 広場が『にぎやかな広場』になった！」＋ 背景デコが1つずつ生えるアニメ
- 判定: SharedPreferences `plaza_level_seen_v1` と比較（永続化）

## 8. 実装優先順位

1. §3 歩いて登場（出会いの実感が最大化・工数S）
2. §7 レベルアップ演出（育成の快感・工数S）
3. §4 カケラ発見（回遊導線・工数S）
4. §6 背景アセット化（人間のドット絵支給待ち）
5. §5 ペルソナ（v1.9）
