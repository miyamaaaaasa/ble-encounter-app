#!/bin/sh
# ローカルから実行する更新デプロイ用スクリプト。
#
# 秘密情報はサーバー側の server/.env（Git管理外）にのみ存在する。
# Caddyfile / compose.yml はどちらも実値を含まず、環境変数参照のみを記述する。
#
# 注意: bcryptハッシュは '$' を含む。docker compose は .env の '$' を変数補間
# しようとするため、.env 側では '$$' にエスケープして記述すること
# （README「管理者パネル」節を参照）。
set -eu
HOST=itoen@153.125.148.69
DIR=/home/itoen/hajimemashite/server

echo "== ファイル転送 =="
scp main.go Dockerfile compose.yml Caddyfile "$HOST:$DIR/"
scp -r admin_panel "$HOST:$DIR/"

echo "== サーバー側で反映 =="
ssh "$HOST" "cd $DIR && \
  test -f .env || { echo '.env が無い。README の管理者パネル節を参照' >&2; exit 1; }; \
  docker compose build && \
  docker compose up -d"

echo "== 完了 =="
