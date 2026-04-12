#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/notify-config"

INPUT=$(cat)

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')

# Stop hook: skip if already active (avoid duplicate notifications)
if [ "$EVENT" = "Stop" ]; then
  ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
  if [ "$ACTIVE" = "true" ]; then
    exit 0
  fi
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
PROJECT=$(basename "$CWD" 2>/dev/null || echo "unknown")

# Skip notifications for active team sessions (leader + teammates)
# Detect team window from config's member panes, then match by window ID
TEAMS_DIR="$HOME/.claude/teams"
if [ -d "$TEAMS_DIR" ] && [ -n "${TMUX_PANE:-}" ]; then
  MY_WIN=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null || true)

  for CONFIG in "$TEAMS_DIR"/*/config.json; do
    [ -f "$CONFIG" ] || continue
    LEAD_SID=$(jq -r '.leadSessionId // ""' "$CONFIG" 2>/dev/null || true)

    # Find team window from any surviving member pane
    TEAM_WIN=""
    while IFS= read -r PANE; do
      [ -n "$PANE" ] || continue
      W=$(tmux display-message -p -t "$PANE" '#{window_id}' 2>/dev/null || true)
      if [ -n "$W" ]; then
        TEAM_WIN="$W"
        break
      fi
    done < <(jq -r '.members[] | select(.tmuxPaneId != "") | .tmuxPaneId' "$CONFIG" 2>/dev/null)

    [ -n "$TEAM_WIN" ] || continue

    if [ "$SESSION_ID" = "$LEAD_SID" ]; then
      # Leader: skip Stop while teammates exist in window, keep others
      if [ "$EVENT" = "Stop" ]; then
        exit 0
      fi
      break
    elif [ -n "$MY_WIN" ] && [ "$MY_WIN" = "$TEAM_WIN" ]; then
      # In team window but not leader → teammate → skip all
      exit 0
    fi
  done
fi

# Resolve session summary from sessions-index.json
SESSION_SUMMARY=""
FIRST_PROMPT=""
PROJECT_DIR_NAME=$(echo "$CWD" | sed 's|/|-|g; s|^-||')
INDEX_FILE="$HOME/.claude/projects/-${PROJECT_DIR_NAME}/sessions-index.json"
if [ -f "$INDEX_FILE" ] && [ -n "$SESSION_ID" ]; then
  SESSION_SUMMARY=$(jq -r --arg sid "$SESSION_ID" \
    '.entries[] | select(.sessionId == $sid) | .summary // ""' \
    "$INDEX_FILE" 2>/dev/null || true)
  if [ -z "$SESSION_SUMMARY" ]; then
    FIRST_PROMPT=$(jq -r --arg sid "$SESSION_ID" \
      '.entries[] | select(.sessionId == $sid) | .firstPrompt // ""' \
      "$INDEX_FILE" 2>/dev/null | head -c 80 || true)
  fi
fi
SESSION_LABEL="${SESSION_SUMMARY:-${FIRST_PROMPT:-${SESSION_ID:0:8}}}"

case "$EVENT" in
  Stop)
    TITLE="タスク完了"
    MSG="Claude の応答が完了しました。確認してください。"
    ;;
  Notification)
    TITLE="権限要求"
    NOTIF_MSG=$(echo "$INPUT" | jq -r '.message // ""')
    NOTIF_TITLE=$(echo "$INPUT" | jq -r '.title // ""')
    MSG="${NOTIF_TITLE}"
    if [ -n "$NOTIF_MSG" ]; then
      MSG="${MSG} - ${NOTIF_MSG}"
    fi
    ;;
  SessionEnd)
    REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"')
    # Skip user-initiated exits
    if [ "$REASON" = "prompt_input_exit" ] || [ "$REASON" = "clear" ] || [ "$REASON" = "logout" ]; then
      exit 0
    fi
    TITLE="予期せぬセッション終了"
    MSG="理由: ${REASON}"
    ;;
  *)
    TITLE="Claude Code"
    MSG="イベント: ${EVENT}"
    ;;
esac

SUBTITLE="${PROJECT} / ${SESSION_LABEL}"

# Skip Stop notification if user is looking at this tmux window
if [ "$EVENT" = "Stop" ]; then
  FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true)
  if [ "$FRONTMOST" = "wezterm-gui" ] && [ -n "${TMUX_PANE:-}" ]; then
    WIN_ACTIVE=$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null || echo "0")
    if [ "$WIN_ACTIVE" = "1" ]; then
      exit 0
    fi
  fi
fi

# Mac desktop notification (tap to show full details in popup)
ESCAPED_MSG=$(echo "$TITLE - $SUBTITLE

$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')

terminal-notifier \
  -title "$TITLE" \
  -subtitle "$SUBTITLE" \
  -message "$MSG" \
  -sound Glass \
  -execute "osascript -e 'display dialog \"$ESCAPED_MSG\" with title \"Claude Code\" buttons {\"OK\"}'" \
  -group "claude-$(date +%s)" \
  2>/dev/null
for i in 1 2; do
  sleep 0.1
  afplay /System/Library/Sounds/Glass.aiff &
done

# Android push notification (ntfy)
curl -s \
  -H "Title: ${TITLE}" \
  -H "Tags: ${PROJECT}" \
  -d "${SUBTITLE}
${MSG}" \
  "ntfy.sh/${NTFY_TOPIC}" > /dev/null 2>&1 &

wait
