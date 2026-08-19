#!/bin/sh

set -eu

message_source="${1:--}"
subject=$(sed -n '1p' "$message_source")
pattern='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([[:alnum:]_.\/-]+\))?!?: .+'

if printf '%s\n' "$subject" | grep -Eq "$pattern"; then
  exit 0
fi

# Keep Git-generated merge and revert commits usable.
if printf '%s\n' "$subject" | grep -Eq '^(Merge |Revert ")'; then
  exit 0
fi

cat >&2 <<'EOF'
Invalid commit message. Use Conventional Commits:

  <type>(optional-scope): short description

Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci,
chore, and revert.

Examples:
  feat(downloads): support resumable transfers
  fix(web): reject private redirect targets
  ci: add tag-based releases
EOF
exit 1
