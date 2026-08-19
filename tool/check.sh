#!/bin/sh

set -eu

mode="${1:-all}"
root=$(git rev-parse --show-toplevel)
cd "$root"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command flutter
require_command dart
require_command node

if [ "$mode" = "commit" ] || [ "$mode" = "all" ]; then
  echo "Checking Dart formatting..."
  dart format --output=none --set-exit-if-changed lib test integration_test

  echo "Running Flutter static analysis..."
  flutter analyze

  echo "Checking Node.js syntax..."
  node --check server.js
  node --check tool/fixture_server.js
fi

if [ "$mode" = "push" ] || [ "$mode" = "all" ]; then
  echo "Running Flutter tests..."
  flutter test

  echo "Running Node.js tests..."
  node --test test/server_test.js

  echo "Building the release Web bundle..."
  flutter build web --release
fi

echo "All $mode checks passed."
