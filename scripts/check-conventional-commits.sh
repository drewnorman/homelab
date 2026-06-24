#!/usr/bin/env sh
set -eu

pattern='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([A-Za-z0-9._/-]+\))?!?: .+'

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/check-conventional-commits.sh --message-file <path>
  scripts/check-conventional-commits.sh --range <rev-range>
EOF
}

subject_from_message_file() {
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d; q' "$1"
}

validate_subject() {
  subject=$1
  label=$2

  if ! printf '%s\n' "$subject" | grep -Eq "$pattern"; then
    cat >&2 <<EOF
Invalid conventional commit subject for ${label}:
  ${subject}

Expected format:
  type(scope): subject

Allowed types:
  build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
EOF
    return 1
  fi
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

case "$1" in
  --message-file)
    subject=$(subject_from_message_file "$2")
    validate_subject "$subject" "$2"
    ;;
  --range)
    git rev-list --no-merges "$2" | while IFS= read -r commit; do
      subject=$(git log -1 --pretty=%s "$commit")
      validate_subject "$subject" "$commit"
    done
    ;;
  *)
    usage
    exit 2
    ;;
esac
