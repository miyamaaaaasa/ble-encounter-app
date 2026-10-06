package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func setup(t *testing.T) {
	t.Helper()
	if err := initDB(filepath.Join(t.TempDir(), "app.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	adminEnabled = true
	adminTokenHash = sha256.Sum256([]byte("test-admin"))
	adminLimiter = newLimiter(10000, 10000)
	apiLimiter = newLimiter(10000, 10000)
	signupLimiter = newLimiter(10000, 10000)
}
func user(t *testing.T, name string) (string, string) {
	t.Helper()
	id, key := randHex(16), randHex(32)
	sum := sha256.Sum256([]byte(key))
	_, err := db.Exec(`INSERT INTO users(id,key_hash,display_name,created_at,updated_at) VALUES(?,?,?,?,?)`, id, sum[:], name, time.Now().Unix(), time.Now().Unix())
	if err != nil {
		t.Fatal(err)
	}
	return id, key
}
func call(h http.HandlerFunc, method, path, body, key string, admin bool) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if key != "" {
		r.Header.Set("Authorization", "Bearer "+key)
	}
	if admin {
		r.Header.Set("X-Admin-Token", "test-admin")
	}
	w := httptest.NewRecorder()
	h(w, r)
	return w
}
func action(t *testing.T, id, act string, want int) {
	t.Helper()
	w := call(withCommon(handleUserAction, "POST", false), "POST", "/admin/api/user-actions", `{"user_id":"`+id+`","action":"`+act+`","confirmed":true}`, "", true)
	if w.Code != want {
		t.Fatalf("action %s %d: %s", act, w.Code, w.Body)
	}
}
func TestJapaneseAndModeration(t *testing.T) {
	setup(t)
	_, key := user(t, "")
	for _, n := range []string{"そら", "山田太郎", "ソラ", "そら123", "Sora", "そらSora"} {
		body, _ := json.Marshal(map[string]string{"display_name": n})
		w := call(withCommon(handleProfile, "POST", true), "POST", "/v1/profile", string(body), key, false)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body)
		}
		var stored string
		db.QueryRow(`SELECT display_name FROM users`).Scan(&stored)
		if stored != n {
			t.Fatal("UTF-8 round trip", stored)
		}
	}
	for _, word := range []string{"禁止語", "Bad"} {
		w := call(handleWords, "POST", "/admin/api/words", `{"word":"`+word+`"}`, "", true)
		if w.Code != 200 {
			t.Fatal(w.Code)
		}
	}
	for _, n := range []string{"禁止語", "禁止語123", "abc禁止語xyz", "bAdName", "ＢＡＤname"} {
		body, _ := json.Marshal(map[string]string{"display_name": n})
		w := call(withCommon(handleProfile, "POST", true), "POST", "/v1/profile", string(body), key, false)
		if w.Code != 422 || strings.Contains(w.Body.String(), "禁止語") {
			t.Fatal("moderation", w.Code, w.Body)
		}
	}
	w := call(handleWords, "DELETE", "/admin/api/words", `{"id":1}`, "", true)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	ok, err := nameAllowed("禁止語")
	if !ok || err != nil {
		t.Fatal(ok, err)
	}
}
func TestTrashRestoreAndRevocation(t *testing.T) {
	setup(t)
	id, key := user(t, "そら")
	other, _ := user(t, "別の人")
	recovery := randHex(32)
	archive := base64.StdEncoding.EncodeToString(append([]byte{97, 49}, make([]byte, 64)...))
	payload, _ := json.Marshal(map[string]string{"recovery_key": recovery, "archive": archive})
	w := call(withCommon(handleSession, "POST", true), "POST", "/v1/account/session", string(payload), key, false)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	action(t, id, "trash", 200)
	var at, deadline int64
	db.QueryRow(`SELECT deleted_at,delete_after FROM users WHERE id=?`, id).Scan(&at, &deadline)
	if deadline-at != int64(retention/time.Second) {
		t.Fatal("deadline")
	}
	w = call(withCommon(handleIssueToken, "POST", true), "POST", "/v1/tokens/issue", "", key, false)
	if w.Code != 403 {
		t.Fatal("old key usable", w.Code)
	}
	w = call(handleReconnect, "POST", "/v1/auth/reconnect", `{"recovery_key":"`+recovery+`"}`, "", false)
	if w.Code != 403 {
		t.Fatal("pending reconnect", w.Code)
	}
	action(t, id, "restore", 200)
	w = call(withCommon(handleIssueToken, "POST", true), "POST", "/v1/tokens/issue", "", key, false)
	if w.Code != 403 {
		t.Fatal("revoked key resurrected")
	}
	w = call(handleReconnect, "POST", "/v1/auth/reconnect", `{"recovery_key":"`+recovery+`"}`, "", false)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	var response struct {
		Key     string `json:"api_key"`
		ID      string `json:"user_id"`
		Archive string `json:"archive"`
	}
	json.Unmarshal(w.Body.Bytes(), &response)
	if response.Key == key || response.ID != id || response.Archive != archive {
		t.Fatal("recovery mismatch")
	}
	w = call(withCommon(handleIssueToken, "POST", true), "POST", "/v1/tokens/issue", "", response.Key, false)
	if w.Code != 200 {
		t.Fatal("new key", w.Code)
	}
	action(t, id, "trash", 200)
	db.Exec(`UPDATE users SET delete_after=? WHERE id=?`, time.Now().Unix()-1, id)
	action(t, id, "restore", 409)
	if err := purgeDeleted(time.Now()); err != nil {
		t.Fatal(err)
	}
	var count int
	db.QueryRow(`SELECT count(*) FROM users WHERE id=?`, id).Scan(&count)
	if count != 0 {
		t.Fatal("not purged")
	}
	db.QueryRow(`SELECT count(*) FROM users WHERE id=?`, other).Scan(&count)
	if count != 1 {
		t.Fatal("other user damaged")
	}
}
func TestAdminAuthorizationAndInput(t *testing.T) {
	setup(t)
	id, key := user(t, "owner")
	for _, h := range []http.HandlerFunc{handleWords, handleTrash, withCommon(handleUserAction, "POST", false)} {
		w := call(h, "POST", "/admin/api/words", `{"user_id":"`+id+`","action":"trash","confirmed":true}`, key, false)
		if w.Code != 401 {
			t.Fatal("nonadmin", w.Code)
		}
	}
	w := call(withCommon(handleUserAction, "POST", false), "POST", "/admin/api/user-actions", `{"user_id":"`+id+`","action":"trash"}`, "", true)
	if w.Code != 400 {
		t.Fatal("unconfirmed")
	}
	if _, err := validArchive("garbage"); err == nil {
		t.Fatal("invalid archive accepted")
	}
}
func TestMigrationPreservesUsers(t *testing.T) {
	setup(t)
	id, _ := user(t, "既存ユーザー")
	if err := initAccounts(); err != nil {
		t.Fatal(err)
	}
	var name string
	if err := db.QueryRow(`SELECT display_name FROM users WHERE id=?`, id).Scan(&name); err != nil || name != "既存ユーザー" {
		t.Fatal("migration lost data")
	}
}

func TestLegacyReconnectAndExactDeadline(t *testing.T) {
	setup(t)
	id, key := user(t, "更新前のユーザー")
	action(t, id, "trash", 200)
	action(t, id, "restore", 200)
	w := call(handleReconnect, "POST", "/v1/auth/reconnect", `{"recovery_key":"`+key+`"}`, "", false)
	if w.Code != 200 {
		t.Fatal("legacy explicit reconnect", w.Code, w.Body)
	}
	w = call(withCommon(handleIssueToken, "POST", true), "POST", "/v1/tokens/issue", "", key, false)
	if w.Code != 403 {
		t.Fatal("legacy bearer revived", w.Code)
	}
	action(t, id, "trash", 200)
	now := time.Now()
	if _, err := db.Exec(`UPDATE users SET delete_after=? WHERE id=?`, now.Unix(), id); err != nil {
		t.Fatal(err)
	}
	action(t, id, "restore", 409)
	if err := purgeDeleted(now); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM users WHERE id=?`, id).Scan(&count); err != nil || count != 0 {
		t.Fatal("exact deadline not purged", count, err)
	}
}
