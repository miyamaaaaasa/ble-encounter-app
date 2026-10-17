# sure. セキュリティ・UX監査 — 2026-10-17

対象: beta1.13.9+62。Superpowersの原因調査・並行レビュー・再現テスト・完了前検証を使用。脆弱性ゼロを保証する監査ではない。

## 確認範囲と修正

| 対象 | 確認した問題・変更 |
|---|---|
| 再接続 | 復元証明を再利用できた。新APIキーと同時に復元証明も交換し、使用済み証明を拒否する。並行再接続は一回にまとめる |
| 復旧耐久性 | 初回登録前に証明をSecureStorageへ保存。再接続前にも交換先を保存し、サーバーcommit後の返信消失から再試行できる |
| API処理ロック | 未認証再接続や通常APIの遅い本文受信が共通ロックを占有した。サイズ制限付きで本文を受信してからロックを取得する |
| 応答キャッシュ | 管理APIを含むJSON応答・認証エラーと管理HTMLにno-storeを指定 |
| 管理ブラウザ | 管理者トークンをlocalStorageへ永続保存していた。旧保存値を除去し、タブ内のsessionStorageへ変更 |
| プロキシログ | 独自X-Admin-Tokenが標準の自動秘匿対象外だった。今後のアクセスログから全ヘッダー・IP・接続元ポートを除外。秘密値は検査出力へ出していない |
| Android保存 | OSバックアップ／端末間転送からアプリ領域を除外。HTTP平文通信も禁止。明示的なアプリ内データ出力は維持 |
| 依存関係 | Goビルドを1.27.2、x/textを0.41.0、x/sysを0.44.0へ更新。モジュール検証の失敗を無視しない。共有サーバー向けにビルド並列度を制限 |
| 手動BLE停止 | foreground復帰で停止が解除された。明示停止を尊重し、再起動後も保存。アカウント解除に伴う内部停止とは区別 |
| 旧Android | OS位置情報サービスOFFを権限許可だけで正常扱いしていた。停止理由と再試行方法を表示。GPS取得処理は追加しない |
| 通知設定 | 検知通知をOFFにしても予約済み通知が残った。対象ID300〜499だけを取り消す |
| 初回画面 | 非同期完了を待たず、自己削除後の再開始が保存中で停滞した。完了を待って再描画、エラー時は再試行可能 |
| データ説明 | 端末内だけに保存するとの誤説明を、サーバー保存と暗号化バックアップの実装に合わせた |

## 認証APIと互換性

`POST /v1/auth/reconnect` は `recovery_key` と新しい64桁hexの `new_recovery_key` を要求する。旧形式は426で更新が必要。既存の通常Bearer認証は維持する。消費済み証明は401、削除待ちアカウントは403。復元しても自動ログインしない。DBスキーマ・30日保持・匿名性を変更しない。

旧匿名端末の救済証明も、再接続成功時に交換する。端末の証明と暗号鍵を紛失した場合の別端末復元を新規に提供するものではない。

## 検証

- Flutter71件合格。認証、暗号化、保存、開門時刻、重複防止、権限、停止、通知、再登録、既存画面を含む。
- 隔離DBのGo9件合格、go vet成功。旧証明の再送・低速本文・キャッシュ漏れを修正前に再現した。
- govulncheck v1.9.0: Go1.27.2標準ライブラリと依存モジュールに既知脆弱性の該当なし。
- Pubの119公開依存をOSVへ版数照会し、該当なし。パッケージ名と版数だけを送信した。
- x/textの旧版はGO-2026-5970の影響版。名前入力にはUTF-8検証があるため、実際の不正入力による悪用成功とは報告しない。保守更新として修正済み版へ移行した。[公式情報](https://pkg.go.dev/vuln/GO-2026-5970)
- 本番反映前にSQLiteの整合性検査付きバックアップと旧APIイメージを保存。反映後health200、未認証API401、管理画面401、no-storeを確認。
- 無害な検証用ヘッダーでログ保護を確認。修正後のログにはheaders/remote_ip/client_ipがない。

静的解析はDartを直接実行しエラーなし、既存警告/info85件。Android署名付きreleaseビルド・3台の更新と5タブQAに合格。Pixel5で明示停止が復帰・再起動後にも維持され、明示起動で再開できることを確認。詳細はREPORT.md。

## 主な変更ファイル

- `server/accounts.go` / `main.go` / `security_test.go` / `accounts_test.go`: 認証・ロック・応答・再現テスト。
- `server/Dockerfile` / `go.mod` / `go.sum` / `Caddyfile` / `admin_panel/admin/index.html`: ランタイム・依存・管理ブラウザ・ログ。
- `lib/services/api_service.dart`: 証明交換・通信断耐久性・single flight。
- `lib/providers/ble_providers.dart` / `ui/home_screen.dart`: 明示停止・OS設定・権限案内。
- `lib/services/notification_service.dart` / `ui/settings_screen.dart`: 通知取消・説明・回復導線。
- `lib/ui/account_access_gate.dart` / `onboarding_screen.dart`: 非同期完了・再登録遷移。
- `android/app/src/main/AndroidManifest.xml` / `res/xml/data_extraction_rules.xml`: バックアップ/転送・平文制限。
- `test/account_lifecycle_test.dart` / `account_gate_ux_test.dart` / `ble_permissions_test.dart` / `ble_stop_persistence_test.dart` / `notification_settings_test.dart` / `ux_regressions_test.dart`: 認証・保存・UX回帰。
- `pubspec.yaml`、各現行資料、`tool/obsidian_sync.py`: バージョン・記録。

## 制限・保留

- **既存アクセスログ**: 検査では検証用を含む8レコードに独自管理ヘッダーを確認。過去ログ書き換えは自動承認レビューが監査情報損失を理由に拒否。原本を保全して機密項目だけ除去する追加処理はユーザーの回答待ち。現在は将来分の保護を実施済み。パスワード・管理者トークンは変更していない。
- iOSの背景広告／明示停止／期限とネイティブキューackは従来の公開阻害項目。MacのSSH timeoutにより今回未コンパイル・未実機検証。Swiftを推測で変更していない。
- 長時間Doze、BLE中継・電波の再送耐性、ルート化端末、共有ホスト管理者によるアクセスは保証しない。トークンを知る者が相手プロフィールを解決できる既存モデルを、距離を暗号学的に証明できる方式とは扱わない。
- 既存の管理者Basic認証・管理者トークン検証、SQLパラメータ化、削除済みキー失効、AES-GCM改ざん検出を維持した。新たな不正ログイン成功や侵害の証拠を確認したという報告ではない。
- 同期で復活した旧コード76件はSHA-256を記録して `C:\Users\ifjvm\Documents\claude\sure-sync-quarantine-20261017` へ退避。恒久的な同期設定の解消は別途必要。未追跡のiOS CIファイルは本変更へ含めない。

証跡: `qa_out/security-*`（非公開、Git対象外）。
