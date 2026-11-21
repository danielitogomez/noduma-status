#!/usr/bin/env bash
# One grouped Telegram message per change of state (Noduma SPEC-047 D9).
#
# Upptime sends one message per site, so one Civo outage sent four. This
# compares each site's status before and after an Upptime run and sends at
# most one message:
#   - sites that went down (from up or degraded), grouped; "all sites down"
#     when every site is, with the open Civo incident if status.civo.com has one;
#   - sites that came back (from down), grouped.
# A site that stays down sends nothing again. Degraded (slow) is shown on the
# status page and in its issue, never sent: it flaps and wakes people for nothing.
#
#   alert.sh BEFORE_FILE HISTORY_DIR
# BEFORE_FILE: "slug status" lines saved before the run (see snapshot below).
# Env: TELEGRAM_BOT_KEY, TELEGRAM_CHAT_ID (missing: print, do not send);
#      CIVO_FEED (default https://status.civo.com/index.xml, "" to skip);
#      STATUS_URL (default https://status.noduma.dev).
set -euo pipefail

snapshot() { # HISTORY_DIR -> "slug status" per site
  for f in "$1"/*.yml; do
    [ -e "$f" ] || continue
    printf '%s %s\n' "$(basename "$f" .yml)" "$(sed -n 's/^status: *//p' "$f" | head -1)"
  done | sort
}

if [ "${1:-}" = snapshot ]; then snapshot "$2"; exit 0; fi

before=$1 history=$2
status_url=${STATUS_URL:-https://status.noduma.dev}
civo_feed=${CIVO_FEED-https://status.civo.com/index.xml}

went_down=() came_up=() total=0 down_now=0
while read -r slug now; do
  [ -n "$slug" ] || continue
  total=$((total + 1))
  [ "$now" = down ] && down_now=$((down_now + 1))
  was=$(awk -v s="$slug" '$1 == s { print $2 }' "$before")
  # A new site with no earlier status counts as up, so it alerts if down.
  [ -n "$was" ] || was=up
  if [ "$now" = down ] && [ "$was" != down ]; then went_down+=("$slug"); fi
  if [ "$now" != down ] && [ "$was" = down ]; then came_up+=("$slug"); fi
done < <(snapshot "$history")

# Open Civo incident: newest feed item from the last 24 hours, not resolved.
civo_incident() {
  [ -n "$civo_feed" ] || return 0
  local xml
  xml=$(curl -fsS --max-time 10 "$civo_feed" 2>/dev/null) || return 0
  printf '%s' "$xml" | awk '
    /<item>/ { item = 1; t = l = d = desc = "" }
    item && /<title>/ { t = $0; gsub(/.*<title>|<\/title>.*/, "", t) }
    item && /<link>/ { l = $0; gsub(/.*<link>|<\/link>.*/, "", l) }
    item && /<pubDate>/ { d = $0; gsub(/.*<pubDate>|<\/pubDate>.*/, "", d) }
    item { desc = desc $0 }
    /<\/item>/ { print t "\t" l "\t" d "\t" (desc ~ /Resolved/ ? "resolved" : "open"); exit }
  ' | while IFS=$'\t' read -r title link date state; do
    [ "$state" = open ] || continue
    epoch=$(date -u -d "$date" +%s 2>/dev/null || date -u -j -f '%a, %d %b %Y %T %z' "$date" +%s 2>/dev/null || echo 0)
    [ $(( $(date -u +%s) - epoch )) -lt 86400 ] || continue
    printf 'Civo reports: %s\n%s\n' "$title" "$link"
  done
}

join() { local IFS=,; printf '%s' "$*" | sed 's/,/, /g'; }

msg=""
if [ ${#went_down[@]} -gt 0 ]; then
  if [ "$down_now" -eq "$total" ] && [ "$total" -gt 1 ]; then
    msg="🟥 Noduma unreachable: all $total public sites are down ($(join "${went_down[@]}")). They share the Civo cluster and load balancer."
  else
    msg="🟥 Down: $(join "${went_down[@]}")"
  fi
  incident=$(civo_incident)
  [ -z "$incident" ] || msg="$msg"$'\n'"$incident"
fi
if [ ${#came_up[@]} -gt 0 ]; then
  up="🟩 Back up: $(join "${came_up[@]}")"
  [ "$down_now" -eq 0 ] && up="$up. All sites are up."
  msg="${msg:+$msg$'\n'}$up"
fi
[ -n "$msg" ] || { echo "No change of state; nothing sent."; exit 0; }
msg="$msg"$'\n'"$status_url"

echo "$msg"
if [ -z "${TELEGRAM_BOT_KEY:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "Telegram secrets not set; not sent."
  exit 0
fi
# The bot key reaches curl on standard input, never in its arguments.
printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_KEY" |
  curl -fsS --max-time 15 --config - --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$msg" --data-urlencode "disable_web_page_preview=true" >/dev/null
echo "Sent to Telegram."
