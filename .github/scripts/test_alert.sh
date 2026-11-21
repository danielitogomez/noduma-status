#!/usr/bin/env bash
# Jail test of alert.sh: temporary folders, no network, no Telegram.
#   bash .github/scripts/test_alert.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

site() { printf 'url: x\nstatus: %s\ncode: 0\n' "$2" > "$tmp/h/$1.yml"; }
run() { # name expected-substring|"NONE"
  out=$(CIVO_FEED="" STATUS_URL=https://s bash "$here/alert.sh" "$tmp/before" "$tmp/h" 2>&1)
  if [ "$2" = NONE ]; then
    case "$out" in *"nothing sent"*) echo "ok   $1" ;; *) echo "FAIL $1: $out"; fail=1 ;; esac
  else
    case "$out" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: $out"; fail=1 ;; esac
  fi
  case "$out" in *"Sent to Telegram"*) echo "FAIL $1: sent without secrets"; fail=1 ;; esac
}
setup() { rm -rf "$tmp/h"; mkdir -p "$tmp/h"; }
before() { bash "$here/alert.sh" snapshot "$tmp/h" > "$tmp/before"; }

setup; site a up; site b up; site c up; before; site a down; site b down; site c down
run "all down groups into one message" "all 3 public sites are down (a, b, c)"

setup; site a down; site b down; site c down; before
run "still down sends nothing" NONE

setup; site a down; site b down; site c down; before; site a up; site b up; site c up
run "all back up in one message" "Back up: a, b, c. All sites are up."

setup; site a up; site b up; before; site b down
run "one site down is named" "Down: b"

setup; site a up; site b down; before; site b degraded
run "down to degraded counts as back" "Back up: b"

setup; site a up; site b up; before; site a degraded
run "degraded alone sends nothing" NONE

setup; site a up; before; site a up; site n down
run "new site already down alerts" "Down: n"

setup; site a down; site b up; before; site a up; site b down
run "one up and one down in one message" "Back up: a"

exit $fail
