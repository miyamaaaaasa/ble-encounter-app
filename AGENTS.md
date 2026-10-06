# Codex / AI assistant instructions

## Project invariants

This app is an anonymous BLE encounter community game, not a social network. Preserve GPS-free operation, rotating tokens, BLE privacy, the presence stage, the 09:00 / 12:00 / 21:00 gates, delayed reveal, and existing data. Do not remove tabs, screens, actions, displayed data or other requirements to simplify a design. Read `PROMPT_GUIDE.md`, `CLAUDE.md`, and the relevant feature docs before changing behavior.

## Obsidian is the live development journal

The vault is `H:\マイドライブ\obsirian`; the canonical app project is `projects/ble-encounter-app/`. For every project-related user turn, record the request, decisions, response and any changes in the session note immediately before finishing the response:

```powershell
python tool/obsidian_sync.py --session "<concise factual summary; omit credentials, tokens, private keys, and sensitive personal data>"
```

The vault's Google Drive Sync plugin has `autoPush` enabled. It batches changes and pushes after roughly 60 seconds; this takes effect after the plugin reloads in Obsidian.

Run a full sync even when there are no code changes. Before recording, check whether relevant source documents or notes are stale against the current repository and update them when evidence supports the correction. Keep unresolved claims explicitly marked unverified. `tool/obsidian_sync.py` mirrors the repo documents, index and Git history; it does not infer facts from chat or independently decide whether prose is accurate. Record factual conversation context in `sessions/YYYY-MM-DD.md`, and reusable requirements/decisions in the relevant source document.

Do not overwrite hand-maintained Obsidian notes. Do not copy secrets into notes. Treat old `projects/アプリ開発/` copies as superseded; the canonical app docs live at `projects/ble-encounter-app/`.

## UI work

The explicit 2026-10-06 specification in `design/world-ui/REQUIREMENTS.md` supersedes the former seven-tab rule: use 今日 / 広場 / ゲーム / 図鑑 / じぶん. Keep バッジ / カケラ / 設定 reachable from these screens. Normal BLE has no scan label; only stopped BLE shows 停止中. Preserve broadcasts, delayed presence, hidden pending identities/counts, existing gate calculation/reveal calls, history and all underlying functions. User-provided concept art is reference only; do not crop it into app assets.

## Session completion

For code changes, follow `WORKFLOW.md`, the existing project rules and test/build requirements. Report what was verified and what remains uncertain. Do not claim a device or background test succeeded from server resolution timestamps alone.
