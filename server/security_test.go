package main

import (
	"crypto/sha256"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestReconnectRotatesRecoveryProof(t *testing.T) {
	setup(t)
	id, key := user(t, "そら")
	proof, next := randHex(32), randHex(32)
	sum := sha256.Sum256([]byte(proof))
	if _, err := db.Exec(`UPDATE users SET recovery_hash=? WHERE id=?`, sum[:], id); err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"recovery_key": proof, "new_recovery_key": next})
	w := call(handleReconnect, "POST", "/v1/auth/reconnect", string(body), "", false)
	if w.Code != 200 {
		t.Fatalf("reconnect: %d %s", w.Code, w.Body)
	}
	w = call(handleReconnect, "POST", "/v1/auth/reconnect", string(body), "", false)
	if w.Code != 401 {
		t.Fatalf("consumed proof replay accepted: %d", w.Code)
	}
	body, _ = json.Marshal(map[string]string{"recovery_key": next, "new_recovery_key": randHex(32)})
	w = call(handleReconnect, "POST", "/v1/auth/reconnect", string(body), "", false)
	if w.Code != 200 {
		t.Fatalf("replacement proof unusable: %d", w.Code)
	}
	w = call(withCommon(handleIssueToken, "POST", true), "POST", "/v1/tokens/issue", "", key, false)
	if w.Code != 403 {
		t.Fatalf("old session usable: %d", w.Code)
	}
}

// A client can trickle a body; it must not own the lock that gates every user.
type stalledBody struct {
	started, release chan struct{}
	once             sync.Once
}

func (b *stalledBody) Read(p []byte) (int, error) {
	b.once.Do(func() { close(b.started) })
	<-b.release
	return 0, io.EOF
}
func (b *stalledBody) Close() error { return nil }

func TestSlowReconnectDoesNotLockAllAccounts(t *testing.T) {
	setup(t)
	body := &stalledBody{started: make(chan struct{}), release: make(chan struct{})}
	r := httptest.NewRequest("POST", "/v1/auth/reconnect", nil)
	r.Body = body
	done := make(chan struct{})
	go func() { handleReconnect(httptest.NewRecorder(), r); close(done) }()
	defer func() { close(body.release); <-done }()
	select {
	case <-body.started:
	case <-time.After(time.Second):
		t.Fatal("request never read")
	}
	if !accountMu.TryRLock() {
		t.Fatal("unauthenticated body holds global account lock")
	}
	accountMu.RUnlock()
}

func TestAdminAndAuthErrorsAreNeverCached(t *testing.T) {
	setup(t)
	for _, h := range []http.HandlerFunc{handleWords, handleTrash, withCommon(handleIssueToken, "POST", true)} {
		w := call(h, "POST", "/", "{}", "", false)
		if w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("sensitive error response is cacheable")
		}
	}
}

func TestSlowProfileBodyDoesNotBlockAccountTransitions(t *testing.T) {
	setup(t)
	_, key := user(t, "slow client")
	body := &stalledBody{started: make(chan struct{}), release: make(chan struct{})}
	r := httptest.NewRequest("POST", "/v1/profile", nil)
	r.Header.Set("Authorization", "Bearer "+key)
	r.Body = body
	done := make(chan struct{})
	go func() { withCommon(handleProfile, "POST", true)(httptest.NewRecorder(), r); close(done) }()
	defer func() { close(body.release); <-done }()
	select {
	case <-body.started:
	case <-time.After(time.Second):
		t.Fatal("request never read")
	}
	if !accountMu.TryLock() {
		t.Fatal("slow profile body holds the shared account lock")
	}
	accountMu.Unlock()
}
