package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"golang.org/x/text/unicode/norm"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

// ponytail: shared RW lock serializes rare deletion/reconnect transitions; use per-user locks if admin throughput grows.
var accountMu sync.RWMutex

const retention = 30 * 24 * time.Hour
const archiveLimit = 1 << 20

func initAccounts() error {
	rows, err := db.Query(`PRAGMA table_info(users)`)
	if err != nil {
		return err
	}
	cols := map[string]bool{}
	for rows.Next() {
		var n int
		var name, typ string
		var nn, pk int
		var d any
		if err = rows.Scan(&n, &name, &typ, &nn, &d, &pk); err != nil {
			rows.Close()
			return err
		}
		cols[name] = true
	}
	rows.Close()
	for _, c := range []struct{ name, def string }{{"deleted_at", "INTEGER"}, {"delete_after", "INTEGER"}, {"recovery_hash", "BLOB"}, {"archive", "BLOB"}} {
		if !cols[c.name] {
			if _, err = db.Exec(`ALTER TABLE users ADD COLUMN ` + c.name + ` ` + c.def); err != nil {
				return err
			}
		}
	}
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS ng_words(id INTEGER PRIMARY KEY AUTOINCREMENT,word TEXT NOT NULL UNIQUE);
 CREATE TABLE IF NOT EXISTS revoked_keys(key_hash BLOB PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE);
 CREATE INDEX IF NOT EXISTS idx_delete_after ON users(delete_after);
 CREATE UNIQUE INDEX IF NOT EXISTS idx_recovery_hash ON users(recovery_hash) WHERE recovery_hash IS NOT NULL;`)
	return err
}

// Normalize case and full-width ASCII without exposing matched words.
func normalized(s string) string {
	s = norm.NFKC.String(s)
	return strings.Map(func(r rune) rune {
		if r >= 0xff01 && r <= 0xff5e {
			r -= 0xfee0
		}
		return unicode.ToLower(r)
	}, s)
}
func nameAllowed(name string) (bool, error) {
	if !utf8.ValidString(name) || len([]rune(name)) == 0 || len([]rune(name)) > maxNameRunes {
		return false, nil
	}
	for _, r := range name {
		if unicode.IsControl(r) || unicode.Is(unicode.Cf, r) {
			return false, nil
		}
	}
	rows, err := db.Query(`SELECT word FROM ng_words`)
	if err != nil {
		return false, err
	}
	defer rows.Close()
	n := normalized(name)
	for rows.Next() {
		var word string
		if err = rows.Scan(&word); err != nil {
			return false, err
		}
		if strings.Contains(n, normalized(word)) {
			return false, nil
		}
	}
	return true, rows.Err()
}
func adminOnly(w http.ResponseWriter, r *http.Request) bool {
	if !adminLimiter.allow(clientIP(r)) {
		writeErr(w, 429, "rate limited")
		return false
	}
	if !authAdmin(r) {
		writeErr(w, 401, "unauthorized")
		return false
	}
	return true
}
func handleWords(w http.ResponseWriter, r *http.Request) {
	if !adminOnly(w, r) {
		return
	}
	switch r.Method {
	case "GET":
		rows, err := db.Query(`SELECT id,word FROM ng_words ORDER BY id`)
		if err != nil {
			writeErr(w, 500, "db error")
			return
		}
		defer rows.Close()
		words := []map[string]any{}
		for rows.Next() {
			var id int
			var word string
			if rows.Scan(&id, &word) != nil {
				writeErr(w, 500, "db error")
				return
			}
			words = append(words, map[string]any{"id": id, "word": word})
		}
		writeJSON(w, 200, words)
	case "POST":
		var req struct {
			Word string `json:"word"`
		}
		if json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req) != nil {
			writeErr(w, 400, "bad request")
			return
		}
		word := strings.TrimSpace(req.Word)
		if !utf8.ValidString(word) || len([]rune(word)) < 1 || len([]rune(word)) > 100 {
			writeErr(w, 400, "invalid word")
			return
		}
		if _, err := db.Exec(`INSERT INTO ng_words(word) VALUES(?) ON CONFLICT(word) DO NOTHING`, word); err != nil {
			writeErr(w, 500, "db error")
			return
		}
		writeJSON(w, 200, map[string]bool{"ok": true})
	case "DELETE":
		var req struct {
			ID int `json:"id"`
		}
		if json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req) != nil || req.ID <= 0 {
			writeErr(w, 400, "bad request")
			return
		}
		if _, err := db.Exec(`DELETE FROM ng_words WHERE id=?`, req.ID); err != nil {
			writeErr(w, 500, "db error")
			return
		}
		writeJSON(w, 200, map[string]bool{"ok": true})
	default:
		writeErr(w, 405, "method not allowed")
	}
}
func handleTrash(w http.ResponseWriter, r *http.Request) {
	if !adminOnly(w, r) {
		return
	}
	if r.Method != "GET" {
		writeErr(w, 405, "method not allowed")
		return
	}
	rows, err := db.Query(`SELECT id,display_name,deleted_at,delete_after FROM users WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC`)
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	defer rows.Close()
	list := []map[string]any{}
	now := time.Now().Unix()
	for rows.Next() {
		var id, name string
		var at, deadline int64
		if rows.Scan(&id, &name, &at, &deadline) != nil {
			writeErr(w, 500, "db error")
			return
		}
		days := (deadline - now + 86399) / 86400
		if days < 0 {
			days = 0
		}
		list = append(list, map[string]any{"id": id, "name": name, "deleted_at": at, "delete_after": deadline, "remaining_days": days})
	}
	writeJSON(w, 200, list)
}
func handleUserAction(w http.ResponseWriter, r *http.Request) {
	accountMu.Lock()
	defer accountMu.Unlock()
	if !adminOnly(w, r) {
		return
	}
	var req struct {
		ID        string `json:"user_id"`
		Action    string `json:"action"`
		Confirmed bool   `json:"confirmed"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req) != nil || len(req.ID) != 32 || !req.Confirmed {
		writeErr(w, 400, "confirmation required")
		return
	}
	tx, err := db.Begin()
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	defer tx.Rollback()
	now := time.Now().Unix()
	var result sql.Result
	if req.Action == "trash" {
		_, err = tx.Exec(`INSERT INTO revoked_keys(key_hash,user_id) SELECT key_hash,id FROM users WHERE id=? AND deleted_at IS NULL`, req.ID)
		if err == nil {
			replacement := sha256.Sum256([]byte(randHex(32)))
			result, err = tx.Exec(`UPDATE users SET deleted_at=?,delete_after=?,recovery_hash=COALESCE(recovery_hash,key_hash),key_hash=? WHERE id=? AND deleted_at IS NULL`, now, now+int64(retention/time.Second), replacement[:], req.ID)
		}
		if err == nil {
			_, err = tx.Exec(`DELETE FROM tokens WHERE user_id=?`, req.ID)
		}
	} else if req.Action == "restore" {
		result, err = tx.Exec(`UPDATE users SET deleted_at=NULL,delete_after=NULL,last_seen_at=0 WHERE id=? AND deleted_at IS NOT NULL AND delete_after>?`, req.ID, now)
	} else {
		writeErr(w, 400, "invalid action")
		return
	}
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	n, _ := result.RowsAffected()
	if n != 1 {
		writeErr(w, 409, "state changed or deadline passed")
		return
	}
	if err = tx.Commit(); err != nil {
		writeErr(w, 500, "db error")
		return
	}
	lastSeenCache.Delete(req.ID)
	writeJSON(w, 200, map[string]bool{"ok": true})
}
func purgeDeleted(now time.Time) error {
	accountMu.Lock()
	defer accountMu.Unlock()
	// Only the deleted user's row and FK-related references are removed.
	// Other users, their compressed archives and local encounter history are untouched.
	_, err := db.Exec(`DELETE FROM users WHERE delete_after IS NOT NULL AND delete_after<=?`, now.Unix())
	return err
}
func revoked(r *http.Request) bool {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return false
	}
	sum := sha256.Sum256([]byte(strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))))
	var one int
	return db.QueryRow(`SELECT 1 FROM revoked_keys WHERE key_hash=?`, sum[:]).Scan(&one) == nil
}

// Session enrollment preserves anonymous auth; recovery proof cannot access normal APIs.
func handleSession(w http.ResponseWriter, r *http.Request) {
	uid, ok := authUser(r)
	if !ok {
		writeErr(w, 401, "unauthorized")
		return
	}
	var req struct {
		Recovery string `json:"recovery_key"`
		Archive  string `json:"archive"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2*archiveLimit)).Decode(&req) != nil || len(req.Recovery) != 64 {
		writeErr(w, 400, "bad request")
		return
	}
	sum := sha256.Sum256([]byte(req.Recovery))
	var data []byte
	var err error
	if req.Archive != "" {
		data, err = validArchive(req.Archive)
		if err != nil {
			writeErr(w, 400, "invalid archive")
			return
		}
	}
	result, err := db.Exec(`UPDATE users SET recovery_hash=?,archive=COALESCE(?,archive) WHERE id=? AND deleted_at IS NULL`, sum[:], data, uid)
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	n, _ := result.RowsAffected()
	if n != 1 {
		writeErr(w, 403, "account_inactive")
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func validArchive(s string) ([]byte, error) {
	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(data) > archiveLimit || len(data) < 30 || data[0] != 97 || data[1] != 49 {
		return nil, io.ErrUnexpectedEOF
	}
	// AES-GCM envelope: version + nonce + ciphertext + authentication tag.
	// Only the owner's device has the encryption key; do not parse private history.
	return data, nil
}

func handleReconnect(w http.ResponseWriter, r *http.Request) {
	accountMu.Lock()
	defer accountMu.Unlock()
	if !signupLimiter.allow(clientIP(r)) {
		writeErr(w, 429, "rate limited")
		return
	}
	var req struct {
		Recovery string `json:"recovery_key"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req) != nil || len(req.Recovery) != 64 {
		writeErr(w, 401, "reconnection unavailable")
		return
	}
	sum := sha256.Sum256([]byte(req.Recovery))
	key := randHex(32)
	hashed := sha256.Sum256([]byte(key))
	tx, err := db.Begin()
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	defer tx.Rollback()
	var id string
	var data []byte
	if err = tx.QueryRow(`SELECT id,archive FROM users WHERE recovery_hash=? AND deleted_at IS NULL`, sum[:]).Scan(&id, &data); err != nil {
		writeErr(w, 403, "reconnection unavailable")
		return
	}
	// Revoke any prior session, even if reconnect is used without a deletion.
	if _, err = tx.Exec(`INSERT OR IGNORE INTO revoked_keys(key_hash,user_id) SELECT key_hash,id FROM users WHERE id=?`, id); err == nil {
		_, err = tx.Exec(`UPDATE users SET key_hash=? WHERE id=? AND deleted_at IS NULL`, hashed[:], id)
	}
	if err != nil {
		writeErr(w, 500, "db error")
		return
	}
	if tx.Commit() != nil {
		writeErr(w, 500, "db error")
		return
	}
	writeJSON(w, 200, map[string]any{"user_id": id, "api_key": key, "archive": base64.StdEncoding.EncodeToString(data)})
}
