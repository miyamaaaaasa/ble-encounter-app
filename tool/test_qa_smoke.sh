#!/usr/bin/env bash
# Regression: a running app behind keyguard is not valid screen QA.
set -eu
cd "$(dirname "$0")/.."
eval "$(sed -n '/^foreground() {/,/^}/p' tool/qa_smoke.sh)"
A() { [ "$*" = "shell dumpsys window" ] || return 1; printf '%s\n' "$FOCUS"; }
FOCUS='mCurrentFocus=Window{abc u0 jp.hajimemashite.app/jp.hajimemashite.app.MainActivity}'
foreground || exit 1
FOCUS='mCurrentFocus=Window{abc u0 com.android.systemui/.EmergencyDialer}'
if foreground; then echo 'FAIL: lock screen accepted'; exit 1; fi
FOCUS=''
if foreground; then echo 'FAIL: missing focus accepted'; exit 1; fi
FILTER=$(sed -n 's/.*grep -E "\(FATAL EXCEPTION[^" ]*.*\)" \\/\1/p' tool/qa_smoke.sh)
[ -n "$FILTER" ]
if printf '%s\n' 'D AndroidRuntime: Shutting down VM' | grep -Eq "$FILTER"; then exit 1; fi
printf '%s\n' 'E AndroidRuntime: FATAL EXCEPTION: main' | grep -Eq "$FILTER"
echo 'PASS: foreground, keyguard, missing focus, normal VM log, fatal crash'
