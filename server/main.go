// はじめましてこんにちは — 自前APIサーバー
//
// Supabase から移行した最小構成のバックエンド。
// 設計方針:
//   - 省リソース: Go 静的バイナリ + SQLite（別プロセスのDB不要、常駐RAM ~20MB）
//   - 省容量: ドット絵は 4bit/px にパックして 128byte で保存（JSON配列比 約6分の1）
//   - 堅牢: APIキーはハッシュ保存、全入力を検証、レート制限、プリペアドステートメント
//   - 匿名性: 個人情報は保持しない。位置情報は一切扱わない（アプリの絶対維持事項）
package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "modernc.org/sqlite"
)

const (
	pixelCount     = 256              // 16x16 ドット絵
	packedPixels   = pixelCount / 2   // 4bit/px → 128 byte
	tokenTTL       = 24 * time.Hour   // BLEトークンの有効期間
	resolveWindow  = 48 * time.Hour   // 解析対象として受け付ける期間
	maxBodyBytes   = 32 << 10         // 32KB（ドット絵込みでも十分）
	maxNameRunes   = 20
	maxResolveList = 200
)

var db *sql.DB

// DBファイルの実パス。バックアップ先やディスク使用量の算出に使う。
var dbPathGlobal string

// ─── レート制限（IP単位のトークンバケット）───────────────────────────────
type bucket struct {
	tokens float64
	last   time.Time
}

type limiter struct {
	mu       sync.Mutex
	buckets  map[string]*bucket
	rate     float64 // 1秒あたりの補充量
	capacity float64
}

func newLimiter(perMinute float64, burst float64) *limiter {
	return &limiter{buckets: map[string]*bucket{}, rate: perMinute / 60.0, capacity: burst}
}

func (l *limiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	b, ok := l.buckets[key]
	if !ok {
		// メモリ肥大防止: 一定数を超えたら古いものを捨てる
		if len(l.buckets) > 10000 {
			for k, v := range l.buckets {
				if now.Sub(v.last) > 10*time.Minute {
					delete(l.buckets, k)
				}
			}
		}
		l.buckets[key] = &bucket{tokens: l.capacity - 1, last: now}
		return true
	}
	b.tokens += now.Sub(b.last).Seconds() * l.rate
	if b.tokens > l.capacity {
		b.tokens = l.capacity
	}
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

var (
	signupLimiter   = newLimiter(5, 5)     // 匿名登録: 5回/分（新規ユーザー乱造の抑止）
	apiLimiter      = newLimiter(120, 60)  // 通常API: 120回/分
	adminLimiter    = newLimiter(20, 10)   // 管理者API: 20回/分（総当たり対策）
	adminTokenHash  [32]byte               // ADMIN_TOKEN のSHA-256（起動時に一度だけ計算）
	adminEnabled    bool                   // ADMIN_TOKEN が設定されている場合のみ有効
)

// ─── ドット絵の圧縮（4bit/px パック）─────────────────────────────────────
// 256個の 0-15 の値を 128 byte に詰める。JSON配列(約800byte)比で約6分の1。
func packPixels(px []int) ([]byte, error) {
	if len(px) != pixelCount {
		return nil, errors.New("pixels must be 256")
	}
	out := make([]byte, packedPixels)
	for i := 0; i < pixelCount; i += 2 {
		a, b := px[i], px[i+1]
		if a < 0 || a > 15 || b < 0 || b > 15 {
			return nil, errors.New("pixel value out of range")
		}
		out[i/2] = byte(a<<4 | b)
	}
	return out, nil
}

func unpackPixels(buf []byte) []int {
	if len(buf) != packedPixels {
		return nil
	}
	out := make([]int, pixelCount)
	for i, b := range buf {
		out[i*2] = int(b >> 4)
		out[i*2+1] = int(b & 0x0f)
	}
	return out
}

// ─── DB ─────────────────────────────────────────────────────────────────
func initDB(path string) error {
	var err error
	// WAL + NORMAL同期: 小規模同時アクセスで高速かつ安全
	db, err = sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(ON)")
	if err != nil {
		return err
	}
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(4)

	schema := `
CREATE TABLE IF NOT EXISTS users (
  id           TEXT PRIMARY KEY,
  key_hash     BLOB NOT NULL,
  display_name TEXT NOT NULL DEFAULT '',
  color_index  INTEGER NOT NULL DEFAULT 0,
  piece_data   BLOB,
  badge_level  INTEGER NOT NULL DEFAULT 0,
  avatar_url   TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_key ON users(key_hash);

CREATE TABLE IF NOT EXISTS tokens (
  token     TEXT PRIMARY KEY,
  user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  issued_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tokens_issued ON tokens(issued_at);
CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id);

CREATE TABLE IF NOT EXISTS broadcasts (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_broadcasts_created ON broadcasts(created_at);
`
	if _, err = db.Exec(schema); err != nil {
		return err
	}

	// 既存DBへの後方互換な列追加。SQLiteに ADD COLUMN IF NOT EXISTS は無いため、
	// 重複時のエラーは無視する（初回以降は毎回エラーになるが害はない）。
	for _, alter := range []string{
		`ALTER TABLE users ADD COLUMN last_seen_at INTEGER NOT NULL DEFAULT 0`,
		// 自己紹介テンプレート。アプリの初期設定で選ぶ4項目を、文字列ではなく
		// 選択肢のインデックスで保持する（自由入力を持たせない＝匿名性の担保）。
		`ALTER TABLE users ADD COLUMN intro_status INTEGER NOT NULL DEFAULT -1`,
		`ALTER TABLE users ADD COLUMN intro_hobby_cat INTEGER NOT NULL DEFAULT -1`,
		`ALTER TABLE users ADD COLUMN intro_hobby_det INTEGER NOT NULL DEFAULT -1`,
		`ALTER TABLE users ADD COLUMN intro_phrase INTEGER NOT NULL DEFAULT -1`,
	} {
		_, _ = db.Exec(alter)
	}
	_, _ = db.Exec(`CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at)`)
	return nil
}

func randHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err) // crypto/rand の失敗は継続不能
	}
	return hex.EncodeToString(b)
}

// ─── 共通ヘルパ ─────────────────────────────────────────────────────────
func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func clientIP(r *http.Request) string {
	// Caddy が付与する X-Forwarded-For の先頭のみ信頼（直前段は自分の管理下）
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.IndexByte(xff, ','); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// Bearer トークンからユーザーを特定する。キーはハッシュ照合（DB漏洩時も鍵は復元不能）
func authUser(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return "", false
	}
	key := strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))
	if len(key) < 32 || len(key) > 128 {
		return "", false
	}
	sum := sha256.Sum256([]byte(key))

	var id string
	var stored []byte
	err := db.QueryRow(`SELECT id, key_hash FROM users WHERE key_hash = ?`, sum[:]).Scan(&id, &stored)
	if err != nil {
		return "", false
	}
	// 念のため定数時間比較
	if subtle.ConstantTimeCompare(sum[:], stored) != 1 {
		return "", false
	}
	touchLastSeen(id)
	return id, true
}

// 最終アクセス時刻の記録。アクティブ人数の算出に使う。
// 毎リクエスト書き込むとSQLiteへの書き込みが増えるため、60秒に1回までに間引く。
// 記録するのは時刻のみで、IPや行動履歴は一切残さない（匿名性の維持）。
var lastSeenCache sync.Map // userID -> time.Time

func touchLastSeen(id string) {
	now := time.Now()
	if v, ok := lastSeenCache.Load(id); ok {
		if now.Sub(v.(time.Time)) < 60*time.Second {
			return
		}
	}
	lastSeenCache.Store(id, now)
	_, _ = db.Exec(`UPDATE users SET last_seen_at = ? WHERE id = ?`, now.Unix(), id)
}

// ─── ハンドラ ───────────────────────────────────────────────────────────

// POST /v1/auth/anon — 匿名ユーザー作成（Supabase の signInAnonymously 相当）
// 返す api_key は端末の SecureStorage に保存され、以後の認証に使う。
// 有効期限を持たないため、旧実装で起きた「約6時間でセッション失効し同期が止まる」問題が起きない。
func handleAuthAnon(w http.ResponseWriter, r *http.Request) {
	if !signupLimiter.allow(clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "too many signups")
		return
	}
	id := randHex(16)
	key := randHex(32)
	sum := sha256.Sum256([]byte(key))
	now := time.Now().Unix()

	_, err := db.Exec(
		`INSERT INTO users (id, key_hash, created_at, updated_at) VALUES (?, ?, ?, ?)`,
		id, sum[:], now, now)
	if err != nil {
		log.Printf("auth/anon insert: %v", err)
		writeErr(w, http.StatusInternalServerError, "server error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"user_id": id, "api_key": key})
}

// POST /v1/tokens/issue — BLEで流す使い捨てトークンを発行（issue_token RPC 相当）
func handleIssueToken(w http.ResponseWriter, r *http.Request) {
	uid, ok := authUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	token := randHex(16) // 16byte = 32hex（BLEペイロードの仕様どおり）
	now := time.Now()
	if _, err := db.Exec(
		`INSERT INTO tokens (token, user_id, issued_at) VALUES (?, ?, ?)`,
		token, uid, now.Unix()); err != nil {
		log.Printf("issue_token: %v", err)
		writeErr(w, http.StatusInternalServerError, "server error")
		return
	}
	// 同一ユーザーの古いトークンを整理（DB肥大防止）。直近3本だけ残す。
	_, _ = db.Exec(`DELETE FROM tokens WHERE user_id = ? AND token NOT IN (
	                  SELECT token FROM tokens WHERE user_id = ? ORDER BY issued_at DESC LIMIT 3)`, uid, uid)

	writeJSON(w, http.StatusOK, map[string]any{
		"token":      token,
		"expires_at": now.Add(tokenTTL).Unix(),
	})
}

type resolveReq struct {
	Tokens []string `json:"tokens"`
}

type resolvedUser struct {
	Token       string `json:"token"`
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name"`
	ColorIndex  int    `json:"color_index"`
	PieceData   []int  `json:"piece_data"`
	BadgeLevel  int    `json:"badge_level"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

// POST /v1/tokens/resolve — 収集したトークンを相手プロフィールへ解決（resolve_tokens RPC 相当）
func handleResolveTokens(w http.ResponseWriter, r *http.Request) {
	uid, ok := authUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req resolveReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad request")
		return
	}
	if len(req.Tokens) == 0 {
		writeJSON(w, http.StatusOK, []resolvedUser{})
		return
	}
	if len(req.Tokens) > maxResolveList {
		req.Tokens = req.Tokens[:maxResolveList]
	}

	// 期限切れトークンの掃除（旧SupabaseのRPCと同じ挙動。DB使用量を自動で抑える）
	_, _ = db.Exec(`DELETE FROM tokens WHERE issued_at < ?`, time.Now().Add(-resolveWindow).Unix())

	// プレースホルダを組み立て（値はバインドするのでSQLインジェクションは発生しない）
	args := make([]any, 0, len(req.Tokens))
	ph := make([]string, 0, len(req.Tokens))
	for _, t := range req.Tokens {
		t = strings.ToLower(strings.TrimSpace(t))
		if len(t) != 32 { // 16byteのhexのみ受理
			continue
		}
		if _, err := hex.DecodeString(t); err != nil {
			continue
		}
		args = append(args, t)
		ph = append(ph, "?")
	}
	if len(args) == 0 {
		writeJSON(w, http.StatusOK, []resolvedUser{})
		return
	}

	q := `SELECT t.token, u.id, u.display_name, u.color_index, u.piece_data, u.badge_level, COALESCE(u.avatar_url,'')
	      FROM tokens t JOIN users u ON u.id = t.user_id
	      WHERE t.token IN (` + strings.Join(ph, ",") + `)`
	rows, err := db.Query(q, args...)
	if err != nil {
		log.Printf("resolve: %v", err)
		writeErr(w, http.StatusInternalServerError, "server error")
		return
	}
	defer rows.Close()

	out := []resolvedUser{}
	for rows.Next() {
		var ru resolvedUser
		var packed []byte
		if err := rows.Scan(&ru.Token, &ru.UserID, &ru.DisplayName, &ru.ColorIndex,
			&packed, &ru.BadgeLevel, &ru.AvatarURL); err != nil {
			continue
		}
		if ru.UserID == uid {
			continue // 自分は除外
		}
		ru.PieceData = unpackPixels(packed)
		out = append(out, ru)
	}
	writeJSON(w, http.StatusOK, out)
}

type profileReq struct {
	DisplayName *string `json:"display_name"`
	ColorIndex  *int    `json:"color_index"`
	PieceData   []int   `json:"piece_data"`
	BadgeLevel  *int    `json:"badge_level"`
	// 自己紹介テンプレート。アプリ側の選択肢インデックスをそのまま持つ。
	// -1 は未回答。自由入力は受け付けない（匿名性の維持）。
	IntroStatus   *int `json:"intro_status"`
	IntroHobbyCat *int `json:"intro_hobby_cat"`
	IntroHobbyDet *int `json:"intro_hobby_det"`
	IntroPhrase   *int `json:"intro_phrase"`
}

// 自己紹介の選択肢インデックスを検証する。-1(未回答) か 0..max の範囲のみ許可。
func introIndex(v int, max int) int {
	if v < 0 || v > max {
		return -1
	}
	return v
}

// POST /v1/profile — 自分のプロフィール更新（users テーブル upsert 相当）
func handleProfile(w http.ResponseWriter, r *http.Request) {
	uid, ok := authUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req profileReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad request")
		return
	}

	sets := []string{"updated_at = ?"}
	args := []any{time.Now().Unix()}

	if req.DisplayName != nil {
		n := strings.TrimSpace(*req.DisplayName)
		if len([]rune(n)) > maxNameRunes {
			n = string([]rune(n)[:maxNameRunes])
		}
		sets = append(sets, "display_name = ?")
		args = append(args, n)
	}
	if req.ColorIndex != nil {
		c := *req.ColorIndex
		if c < 0 || c > 63 {
			c = 0
		}
		sets = append(sets, "color_index = ?")
		args = append(args, c)
	}
	if req.BadgeLevel != nil {
		b := *req.BadgeLevel
		if b < 0 {
			b = 0
		}
		if b > 255 {
			b = 255
		}
		sets = append(sets, "badge_level = ?")
		args = append(args, b)
	}
	// 選択肢の個数はアプリ側の定義に合わせる（status 8 / category 8 / detail 4 / phrase 8）
	for _, f := range []struct {
		val *int
		col string
		max int
	}{
		{req.IntroStatus, "intro_status", 7},
		{req.IntroHobbyCat, "intro_hobby_cat", 7},
		{req.IntroHobbyDet, "intro_hobby_det", 3},
		{req.IntroPhrase, "intro_phrase", 7},
	} {
		if f.val != nil {
			sets = append(sets, f.col+" = ?")
			args = append(args, introIndex(*f.val, f.max))
		}
	}
	if req.PieceData != nil {
		packed, err := packPixels(req.PieceData)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid piece_data")
			return
		}
		sets = append(sets, "piece_data = ?")
		args = append(args, packed)
	}

	args = append(args, uid)
	if _, err := db.Exec(`UPDATE users SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...); err != nil {
		log.Printf("profile: %v", err)
		writeErr(w, http.StatusInternalServerError, "server error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// GET /v1/health — 監視用（認証不要・内部情報は出さない）
// ─── 管理者ブロードキャスト（文化祭運営向け）───────────────────────────
//
// 管理者が任意のタイトル・本文を配信し、アプリ利用者は起動中に定期取得して
// バナー表示する（プッシュ通知ではなくポーリング。アプリを完全に閉じている
// 間は届かない。FCM等の外部サービス導入を避け、自前サーバー完結を優先）。
//
// 認証は共有シークレット（環境変数 ADMIN_TOKEN）を X-Admin-Token ヘッダで
// 照合する定数時間比較。ユーザーのBearerキーとは別体系（管理者はアプリの
// ユーザーではないため）。ADMIN_TOKEN 未設定時はエンドポイント自体を無効化し、
// 誤って空文字と比較して突破されることを防ぐ。

func authAdmin(r *http.Request) bool {
	if !adminEnabled {
		return false
	}
	tok := r.Header.Get("X-Admin-Token")
	if tok == "" {
		return false
	}
	sum := sha256.Sum256([]byte(tok))
	return subtle.ConstantTimeCompare(sum[:], adminTokenHash[:]) == 1
}

type broadcastReq struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// POST /admin/broadcast — 全利用者への配信を1件作成する
func handleAdminBroadcast(w http.ResponseWriter, r *http.Request) {
	if !adminLimiter.allow(clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "rate limited")
		return
	}
	if !authAdmin(r) {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req broadcastReq
	if err := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	if req.Title == "" || len([]rune(req.Title)) > 40 {
		writeErr(w, http.StatusBadRequest, "title must be 1-40 chars")
		return
	}
	if req.Body == "" || len([]rune(req.Body)) > 200 {
		writeErr(w, http.StatusBadRequest, "body must be 1-200 chars")
		return
	}
	res, err := db.Exec(`INSERT INTO broadcasts (title, body, created_at) VALUES (?, ?, ?)`,
		req.Title, req.Body, time.Now().Unix())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db error")
		return
	}
	id, _ := res.LastInsertId()
	log.Printf("admin: broadcast #%d created", id)
	writeJSON(w, http.StatusOK, map[string]any{"id": id})
}

// GET /v1/broadcasts?since=<id> — 未読分の配信一覧（アプリが定期ポーリング）
// 通常ユーザーのBearer認証を要求する（匿名性維持・全API認証必須の方針に合わせる）。
func handleBroadcasts(w http.ResponseWriter, r *http.Request) {
	if _, ok := authUser(r); !ok {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	since := int64(0)
	if s := r.URL.Query().Get("since"); s != "" {
		if v, err := strconv.ParseInt(s, 10, 64); err == nil && v >= 0 {
			since = v
		}
	}
	rows, err := db.Query(
		`SELECT id, title, body, created_at FROM broadcasts WHERE id > ? ORDER BY id ASC LIMIT 20`,
		since)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db error")
		return
	}
	defer rows.Close()

	out := []map[string]any{}
	for rows.Next() {
		var id, createdAt int64
		var title, body string
		if err := rows.Scan(&id, &title, &body, &createdAt); err != nil {
			continue
		}
		out = append(out, map[string]any{
			"id": id, "title": title, "body": body, "created_at": createdAt,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

// ─── サーバー監視（管理者向け）─────────────────────────────────────────
//
// 共有サーバーなので外部の監視エージェントを常駐させず、API自身で数値を出す。
// コンテナ内から見える /proc はホストのものなので、ホスト全体の負荷が取れる。

// CPU使用率は瞬間値が取れない。5秒ごとにサンプリングして最新値を保持する。
var cpuPercent struct {
	sync.Mutex
	value float64
}

// /proc/stat の1行目から (総時間, アイドル時間) を得る
func readCPUTimes() (total, idle uint64, err error) {
	b, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0, err
	}
	line := strings.SplitN(string(b), "\n", 2)[0]
	fields := strings.Fields(line)
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0, 0, errors.New("unexpected /proc/stat")
	}
	for i, f := range fields[1:] {
		v, e := strconv.ParseUint(f, 10, 64)
		if e != nil {
			continue
		}
		total += v
		if i == 3 { // idle列
			idle = v
		}
	}
	return total, idle, nil
}

func startCPUSampler() {
	go func() {
		prevTotal, prevIdle, err := readCPUTimes()
		if err != nil {
			log.Printf("cpu sampler disabled: %v", err)
			return
		}
		for {
			time.Sleep(5 * time.Second)
			total, idle, err := readCPUTimes()
			if err != nil {
				continue
			}
			dt, di := total-prevTotal, idle-prevIdle
			prevTotal, prevIdle = total, idle
			if dt == 0 {
				continue
			}
			cpuPercent.Lock()
			cpuPercent.value = (1.0 - float64(di)/float64(dt)) * 100.0
			cpuPercent.Unlock()
		}
	}()
}

// /proc/meminfo から MemTotal と MemAvailable を取る（KB単位）
func readMemInfo() (totalKB, availKB uint64) {
	b, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	for _, line := range strings.Split(string(b), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		v, _ := strconv.ParseUint(fields[1], 10, 64)
		switch fields[0] {
		case "MemTotal:":
			totalKB = v
		case "MemAvailable:":
			availKB = v
		}
	}
	return
}

// /data を含むファイルシステム（＝ホストのディスク）の使用状況
func readDisk(path string) (totalBytes, freeBytes uint64) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, 0
	}
	return st.Blocks * uint64(st.Bsize), st.Bavail * uint64(st.Bsize)
}

func pct(used, total uint64) float64 {
	if total == 0 {
		return 0
	}
	return float64(used) / float64(total) * 100.0
}

// バックアップ世代の一覧（新しい順）
func listBackups() []map[string]any {
	dir := filepathJoin(dbPathGlobal, "backups")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return []map[string]any{}
	}
	names := []string{}
	for _, e := range entries {
		if !e.IsDir() && strings.HasPrefix(e.Name(), "app-") && strings.HasSuffix(e.Name(), ".db") {
			names = append(names, e.Name())
		}
	}
	sortStrings(names)
	out := []map[string]any{}
	for i := len(names) - 1; i >= 0; i-- { // 新しい順
		fi, err := os.Stat(dir + "/" + names[i])
		if err != nil {
			continue
		}
		out = append(out, map[string]any{
			"name": names[i], "size": fi.Size(), "mtime": fi.ModTime().Unix(),
		})
	}
	return out
}

// GET /admin/api/stats — 稼働状況のサマリー
func handleAdminStats(w http.ResponseWriter, r *http.Request) {
	if !adminLimiter.allow(clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "rate limited")
		return
	}
	if !authAdmin(r) {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	now := time.Now()
	count := func(q string, args ...any) int {
		var n int
		_ = db.QueryRow(q, args...).Scan(&n)
		return n
	}

	memTotal, memAvail := readMemInfo()
	diskTotal, diskFree := readDisk(filepathJoin(dbPathGlobal, ""))
	cpuPercent.Lock()
	cpu := cpuPercent.value
	cpuPercent.Unlock()

	var dbSize int64
	if fi, err := os.Stat(dbPathGlobal); err == nil {
		dbSize = fi.Size()
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"users": map[string]any{
			"total":      count("SELECT count(*) FROM users"),
			"active_5m":  count("SELECT count(*) FROM users WHERE last_seen_at > ?", now.Add(-5*time.Minute).Unix()),
			"active_1h":  count("SELECT count(*) FROM users WHERE last_seen_at > ?", now.Add(-time.Hour).Unix()),
			"active_24h": count("SELECT count(*) FROM users WHERE last_seen_at > ?", now.Add(-24*time.Hour).Unix()),
			"with_name":  count("SELECT count(*) FROM users WHERE display_name <> ''"),
			"with_piece": count("SELECT count(*) FROM users WHERE piece_data IS NOT NULL"),
		},
		"tokens":     count("SELECT count(*) FROM tokens"),
		"broadcasts": count("SELECT count(*) FROM broadcasts"),
		"host": map[string]any{
			"cpu_percent":  cpu,
			"mem_total":    memTotal * 1024,
			"mem_used":     (memTotal - memAvail) * 1024,
			"mem_percent":  pct(memTotal-memAvail, memTotal),
			"disk_total":   diskTotal,
			"disk_used":    diskTotal - diskFree,
			"disk_percent": pct(diskTotal-diskFree, diskTotal),
		},
		"db_size": dbSize,
		"backups": listBackups(),
		"now":     now.Unix(),
	})
}

// POST /admin/api/backup — その場でバックアップを作る
//
// 作るのは**サーバー内のローカル複製のみ**。Google Driveへの退避はホスト側の
// cron(毎日4:10)が担当で、ここからは起動できない（起動するにはコンテナへ
// dockerソケットを渡す必要があり、共有サーバーでは危険なため採らない）。
func handleAdminBackup(w http.ResponseWriter, r *http.Request) {
	if !adminLimiter.allow(clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "rate limited")
		return
	}
	if !authAdmin(r) {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	dir := filepathJoin(dbPathGlobal, "backups")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		writeErr(w, http.StatusInternalServerError, "cannot create backup dir")
		return
	}
	// 手動実行は同日でも上書きせず時刻付きで残す（cronの日次分と区別するため）
	dst := dir + "/app-" + time.Now().Format("20060102-150405") + ".db"
	if _, err := db.Exec("VACUUM INTO ?", dst); err != nil {
		log.Printf("manual backup: %v", err)
		writeErr(w, http.StatusInternalServerError, "backup failed")
		return
	}
	var size int64
	if fi, err := os.Stat(dst); err == nil {
		size = fi.Size()
	}
	pruneBackups(dir, 14) // 手動分が増えるので世代上限を広げる
	log.Printf("admin: manual backup created (%d bytes)", size)
	writeJSON(w, http.StatusOK, map[string]any{
		"name": dst[strings.LastIndex(dst, "/")+1:], "size": size,
	})
}

// GET /admin/api/users — 利用者一覧（表示名・色・自己紹介・ドット絵）
//
// 返すのは利用者が「すれ違った相手に見せる前提で設定した情報」だけ。
// APIキー・すれ違い履歴・IP・位置情報は一切返さない（匿名性の絶対維持）。
func handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	if !adminLimiter.allow(clientIP(r)) {
		writeErr(w, http.StatusTooManyRequests, "rate limited")
		return
	}
	if !authAdmin(r) {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	limit := 50
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 200 {
		limit = v
	}
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}

	rows, err := db.Query("SELECT id, display_name, color_index, piece_data, badge_level,"+
		" created_at, last_seen_at, intro_status, intro_hobby_cat, intro_hobby_det, intro_phrase"+
		" FROM users ORDER BY last_seen_at DESC, created_at DESC LIMIT ? OFFSET ?", limit, offset)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db error")
		return
	}
	defer rows.Close()

	out := []map[string]any{}
	for rows.Next() {
		var id, name string
		var color, badge, introS, introHC, introHD, introP int
		var createdAt, lastSeen int64
		var piece []byte
		if err := rows.Scan(&id, &name, &color, &piece, &badge, &createdAt, &lastSeen,
			&introS, &introHC, &introHD, &introP); err != nil {
			continue
		}
		short := id
		if len(short) > 8 {
			short = short[:8]
		}
		out = append(out, map[string]any{
			// IDは先頭8文字のみ（照合には足り、全体は見せない）
			"id":         short,
			"name":       name,
			"color":      color,
			"badge":      badge,
			"created_at": createdAt,
			"last_seen":  lastSeen,
			"pixels":     unpackPixels(piece),
			"intro":      []int{introS, introHC, introHD, introP},
		})
	}
	var total int
	_ = db.QueryRow("SELECT count(*) FROM users").Scan(&total)
	writeJSON(w, http.StatusOK, map[string]any{"total": total, "users": out})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := db.Ping(); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "db down")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ─── ミドルウェア ───────────────────────────────────────────────────────
func withCommon(next http.HandlerFunc, method string, limited bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != method {
			w.Header().Set("Allow", method)
			writeErr(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}
		if limited && !apiLimiter.allow(clientIP(r)) {
			writeErr(w, http.StatusTooManyRequests, "rate limited")
			return
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		next(w, r)
	}
}

// dbPath と同じディレクトリ配下に sub を作ったパスを返す（path/filepath を持ち込まない軽量版）
func filepathJoin(dbPath, sub string) string {
	i := strings.LastIndexByte(dbPath, '/')
	if i < 0 {
		return sub
	}
	return dbPath[:i] + "/" + sub
}

// 指定世代数を超える古いバックアップを削除する（ディスクを一定量に保つ）
func pruneBackups(dir string, keep int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasPrefix(e.Name(), "app-") && strings.HasSuffix(e.Name(), ".db") {
			names = append(names, e.Name())
		}
	}
	if len(names) <= keep {
		return
	}
	sortStrings(names) // 日付形式なので辞書順＝時系列順
	for _, n := range names[:len(names)-keep] {
		_ = os.Remove(dir + "/" + n)
	}
}

func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}

func main() {
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "/data/app.db"
	}
	dbPathGlobal = dbPath
	if err := initDB(dbPath); err != nil {
		log.Fatalf("db init: %v", err)
	}
	defer db.Close()

	// ADMIN_TOKEN 未設定なら管理者エンドポイントは常に401を返す（安全側デフォルト）
	if tok := os.Getenv("ADMIN_TOKEN"); tok != "" {
		adminTokenHash = sha256.Sum256([]byte(tok))
		adminEnabled = true
		log.Println("admin: broadcast endpoint enabled")
	} else {
		log.Println("admin: ADMIN_TOKEN not set — broadcast endpoint disabled")
	}

	startCPUSampler()

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", withCommon(handleHealth, http.MethodGet, false))
	mux.HandleFunc("/v1/auth/anon", withCommon(handleAuthAnon, http.MethodPost, false))
	mux.HandleFunc("/v1/tokens/issue", withCommon(handleIssueToken, http.MethodPost, true))
	mux.HandleFunc("/v1/tokens/resolve", withCommon(handleResolveTokens, http.MethodPost, true))
	mux.HandleFunc("/v1/profile", withCommon(handleProfile, http.MethodPost, true))
	mux.HandleFunc("/v1/broadcasts", withCommon(handleBroadcasts, http.MethodGet, true))
	// 管理者API。Caddy側でBasic認証を通した上で、さらにX-Admin-Tokenを検証する。
	mux.HandleFunc("/admin/api/broadcast", withCommon(handleAdminBroadcast, http.MethodPost, false))
	mux.HandleFunc("/admin/api/stats", withCommon(handleAdminStats, http.MethodGet, false))
	mux.HandleFunc("/admin/api/users", withCommon(handleAdminUsers, http.MethodGet, false))
	mux.HandleFunc("/admin/api/backup", withCommon(handleAdminBackup, http.MethodPost, false))
	// 旧パス（ラズパイ等の既存スクリプト互換）
	mux.HandleFunc("/admin/broadcast", withCommon(handleAdminBroadcast, http.MethodPost, false))

	srv := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    8 << 10,
	}

	// 定期メンテナンス: 期限切れトークンの掃除 + バックアップ世代管理。
	// 別プロセス・別イメージを立てずにAPI内で完結させ、常駐リソースを増やさない。
	go func() {
		backupDir := filepathJoin(dbPath, "backups")
		_ = os.MkdirAll(backupDir, 0o700)
		time.Sleep(30 * time.Second) // 起動直後に1回（デプロイ直後の復旧点を確保）
		for {
			if res, err := db.Exec(`DELETE FROM tokens WHERE issued_at < ?`,
				time.Now().Add(-resolveWindow).Unix()); err == nil {
				n, _ := res.RowsAffected()
				if n > 0 {
					log.Printf("gc: removed %d expired tokens", n)
				}
				_, _ = db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`)
			}

			// VACUUM INTO は断片化を除いた最小サイズの複製を作る（圧縮を兼ねる）
			dst := backupDir + "/app-" + time.Now().Format("20060102") + ".db"
			_ = os.Remove(dst) // 同日分は上書き
			if _, err := db.Exec(`VACUUM INTO ?`, dst); err != nil {
				log.Printf("backup: %v", err)
			} else {
				pruneBackups(backupDir, 7) // 7世代だけ残す
			}

			time.Sleep(6 * time.Hour)
		}
	}()

	go func() {
		log.Println("api listening on :8080")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	log.Println("shutdown complete")
}
