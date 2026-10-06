#!/usr/bin/env bash
# Run manually from the Mac GUI Terminal; never installs a LaunchAgent.
set -euo pipefail
export PATH="$HOME/development/flutter/bin:$HOME/development/ruby/portable-ruby/3.4.5/bin:$HOME/development/gems/bin:$PATH"
export GEM_HOME="$HOME/development/gems"
export LANG=en_US.UTF-8
cd "$(dirname "$0")/.."
flutter pub get
if [ "$#" -gt 0 ]; then
  flutter run --release -d "$1"
else
  flutter build ios --release
fi
