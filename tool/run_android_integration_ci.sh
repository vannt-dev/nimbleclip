#!/bin/sh

set -eu

fixture_log="${RUNNER_TEMP:-/tmp}/nimbleclip-fixture-server.log"
node tool/fixture_server.js >"$fixture_log" 2>&1 &
fixture_pid=$!

cleanup() {
  kill "$fixture_pid" 2>/dev/null || true
  wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=1
while [ "$attempt" -le 60 ]; do
  if curl --fail --silent http://127.0.0.1:8097/health |
      grep --quiet nimbleclip-fixture; then
    break
  fi
  if ! kill -0 "$fixture_pid" 2>/dev/null; then
    cat "$fixture_log"
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if ! curl --fail --silent http://127.0.0.1:8097/health |
    grep --quiet nimbleclip-fixture; then
  cat "$fixture_log"
  echo 'Fixture server did not become healthy within 60 seconds.' >&2
  exit 1
fi

flutter test \
  integration_test/android_storage_test.dart \
  integration_test/slideshow_render_test.dart \
  -d emulator-5554
