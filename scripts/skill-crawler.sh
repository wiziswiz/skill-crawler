#!/usr/bin/env bash
# skill-crawler.sh — Check upstream repos for updates, notify via Telegram
# Part of the Skill Crawler skill for OpenClaw
# https://github.com/wiziswiz/skill-crawler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# --- Locate config ---
CONFIG_FILE=""
for candidate in \
  "$SKILL_DIR/skill-crawler.config.json" \
  "$HOME/.openclaw/skills/skill-crawler/skill-crawler.config.json"; do
  if [[ -f "$candidate" ]]; then
    CONFIG_FILE="$candidate"
    break
  fi
done

if [[ -z "$CONFIG_FILE" ]]; then
  echo "ERROR: skill-crawler.config.json not found. Copy the .example and fill it in." >&2
  exit 1
fi

# --- Read Telegram token from openclaw.json ---
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
if [[ ! -f "$OPENCLAW_JSON" ]]; then
  echo "ERROR: $OPENCLAW_JSON not found. Is OpenClaw installed?" >&2
  exit 1
fi

TELEGRAM_TOKEN="$(python3 -c "import json; print(json.load(open('$OPENCLAW_JSON'))['channels']['telegram']['botToken'])" 2>/dev/null)" || {
  echo "ERROR: Could not read Telegram bot token from $OPENCLAW_JSON" >&2
  exit 1
}

CHAT_ID="$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('$CONFIG_FILE')))['telegram_chat_id'])" 2>/dev/null)" || {
  echo "ERROR: Could not read telegram_chat_id from config" >&2
  exit 1
}

if [[ "$CHAT_ID" == "YOUR_CHAT_ID" ]]; then
  echo "ERROR: telegram_chat_id is still set to placeholder. Edit your config." >&2
  exit 1
fi

# --- State directory for dedup ---
STATE_DIR="$HOME/.openclaw/skills/skill-crawler/.state"
mkdir -p "$STATE_DIR"

# --- Parse config with Python (portable, no jq dependency) ---
read_config() {
  python3 -c "
import json, sys, os

with open(os.environ['SC_CONFIG']) as f:
    config = json.load(f)

section = sys.argv[1]
items = config.get(section, [])
home = os.path.expanduser('~')

for item in items:
    if section == 'installed_skills':
        local_path = item.get('local_path', '').replace('~', home)
        print(f\"{item['name']}|{local_path}|{item['github_repo']}\")
    elif section == 'watch_repos':
        ctx = item.get('context', 'no context provided')
        print(f\"{item['name']}|{item['github_repo']}|{ctx}\")
" "$1"
}

export SC_CONFIG="$CONFIG_FILE"

# --- GitHub API: get latest commit SHA for a repo ---
gh_latest_sha() {
  local repo="$1"
  curl -sf --max-time 10 \
    "https://api.github.com/repos/$repo/commits?per_page=1" 2>/dev/null \
    | python3 -c "import json,sys; data=json.load(sys.stdin); print(data[0]['sha'])" 2>/dev/null
}

gh_latest_commit_info() {
  local repo="$1"
  curl -sf --max-time 10 \
    "https://api.github.com/repos/$repo/commits?per_page=1" 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
c = data[0]
sha = c['sha'][:7]
msg = c['commit']['message'].split('\n')[0][:80]
author = c['commit']['author']['name']
print(f'{sha}|{msg}|{author}')
" 2>/dev/null
}

# --- Check installed skills ---
INSTALLED_UPDATES=""

while IFS='|' read -r name local_path github_repo; do
  [[ -z "$name" ]] && continue
  
  # Expand ~ in local_path
  local_path="${local_path/#\~/$HOME}"
  
  state_file="$STATE_DIR/installed_${name}.sha"
  new_sha=""
  behind=""
  
  # Try git fetch first if .git exists
  if [[ -d "$local_path/.git" ]]; then
    if git -C "$local_path" fetch origin 2>/dev/null; then
      local_sha="$(git -C "$local_path" rev-parse HEAD 2>/dev/null)"
      remote_sha="$(git -C "$local_path" rev-parse FETCH_HEAD 2>/dev/null)"
      
      if [[ -n "$local_sha" && -n "$remote_sha" ]]; then
        if [[ "$local_sha" != "$remote_sha" ]]; then
          count="$(git -C "$local_path" rev-list HEAD..FETCH_HEAD --count 2>/dev/null || echo "?")"
          new_sha="$remote_sha"
          behind="$count commits behind"
        else
          new_sha="$local_sha"
        fi
      fi
    else
      echo "WARN: git fetch failed for $name, falling back to API" >&2
      new_sha="$(gh_latest_sha "$github_repo" || true)"
    fi
  else
    # No local .git — use GitHub API
    new_sha="$(gh_latest_sha "$github_repo" || true)"
  fi
  
  if [[ -z "$new_sha" ]]; then
    echo "WARN: Could not check $name ($github_repo) — skipping" >&2
    continue
  fi
  
  # Dedup: check against last known SHA
  old_sha=""
  [[ -f "$state_file" ]] && old_sha="$(cat "$state_file")"
  
  if [[ "$new_sha" != "$old_sha" && -n "$old_sha" ]]; then
    # Get commit info
    info="$(gh_latest_commit_info "$github_repo" || echo "unknown|unknown|unknown")"
    IFS='|' read -r short_sha msg author <<< "$info"
    
    detail=""
    [[ -n "$behind" ]] && detail=" ($behind)"
    INSTALLED_UPDATES+="• *${name}*${detail}
  \`${short_sha}\` ${msg} — ${author}
  → \`cd ${local_path} && git pull\`
"
  fi
  
  # Save current SHA
  echo "$new_sha" > "$state_file"

done <<< "$(read_config installed_skills)"

# --- Check watch repos ---
WATCH_UPDATES=""

while IFS='|' read -r name github_repo context; do
  [[ -z "$name" ]] && continue
  
  state_file="$STATE_DIR/watch_${name}.sha"
  
  new_sha="$(gh_latest_sha "$github_repo" || true)"
  if [[ -z "$new_sha" ]]; then
    echo "WARN: Could not check watch repo $name ($github_repo) — skipping" >&2
    continue
  fi
  
  old_sha=""
  [[ -f "$state_file" ]] && old_sha="$(cat "$state_file")"
  
  if [[ "$new_sha" != "$old_sha" && -n "$old_sha" ]]; then
    info="$(gh_latest_commit_info "$github_repo" || echo "unknown|unknown|unknown")"
    IFS='|' read -r short_sha msg author <<< "$info"
    
    WATCH_UPDATES+="• *${name}* (${github_repo})
  \`${short_sha}\` ${msg} — ${author}
  _Context: ${context}_
"
  fi
  
  echo "$new_sha" > "$state_file"

done <<< "$(read_config watch_repos)"

# --- Build and send message ---
if [[ -z "$INSTALLED_UPDATES" && -z "$WATCH_UPDATES" ]]; then
  echo "No updates found. Silent exit."
  exit 0
fi

MSG="🕷️ *Skill Crawler — Updates Found*
"

if [[ -n "$INSTALLED_UPDATES" ]]; then
  MSG+="
📦 *Installed Skills*
${INSTALLED_UPDATES}"
fi

if [[ -n "$WATCH_UPDATES" ]]; then
  MSG+="
👀 *Watch List*
${WATCH_UPDATES}"
fi

MSG+="
_Run: $(date '+%Y-%m-%d %H:%M %Z')_"

# Send via Telegram Bot API
PAYLOAD="$(SC_CHAT_ID="$CHAT_ID" python3 -c "
import json, sys, os
msg = sys.stdin.read()
print(json.dumps({
    'chat_id': os.environ['SC_CHAT_ID'],
    'text': msg,
    'parse_mode': 'Markdown',
    'disable_web_page_preview': True
}))
" <<< "$MSG")"

response="$(curl -sf --max-time 15 \
  -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)" || {
  echo "ERROR: Failed to send Telegram message" >&2
  exit 1
}

echo "Telegram notification sent successfully."
