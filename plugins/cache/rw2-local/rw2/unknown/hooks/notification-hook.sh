#!/bin/bash

# Ralph Wiggum Notification Hook
# Sends desktop notifications for important events
# Supports macOS (terminal-notifier/osascript) and Linux (notify-send)

set -euo pipefail

RALPH_STATE_FILE=".claude/ralph-loop.local.md"

# Only act if ralph-loop is active
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Read notification type from stdin or arguments
NOTIFICATION_TYPE="${1:-iteration}"
NOTIFICATION_MESSAGE="${2:-}"

# Parse current state
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
CHECKPOINT_INTERVAL=$(echo "$FRONTMATTER" | grep '^checkpoint_interval:' | sed 's/checkpoint_interval: *//')

# Determine notification content based on type
TITLE="Ralph Wiggum"
BODY=""
URGENCY="normal"

case "$NOTIFICATION_TYPE" in
  "iteration")
    # Only notify at checkpoints or every 10 iterations
    if [[ "${CHECKPOINT_INTERVAL:-0}" -gt 0 ]]; then
      if (( ITERATION % CHECKPOINT_INTERVAL != 0 )); then
        exit 0  # Not a checkpoint, skip notification
      fi
      BODY="Checkpoint at iteration $ITERATION"
    elif (( ITERATION % 10 == 0 )); then
      BODY="Reached iteration $ITERATION"
    else
      exit 0  # Not a notable iteration
    fi
    ;;
  "checkpoint")
    BODY="Checkpoint at iteration $ITERATION - Review required"
    URGENCY="critical"
    ;;
  "complete")
    BODY="Task completed at iteration $ITERATION!"
    TITLE="Ralph Complete"
    ;;
  "error")
    BODY="${NOTIFICATION_MESSAGE:-Errors detected at iteration $ITERATION}"
    URGENCY="critical"
    ;;
  "stuck")
    BODY="Loop appears stuck at iteration $ITERATION"
    URGENCY="critical"
    ;;
  "custom")
    BODY="$NOTIFICATION_MESSAGE"
    ;;
  *)
    BODY="$NOTIFICATION_TYPE: $NOTIFICATION_MESSAGE"
    ;;
esac

# Send notification based on OS
send_notification() {
  local title="$1"
  local body="$2"
  local urgency="$3"

  # macOS
  if command -v terminal-notifier &> /dev/null; then
    terminal-notifier -title "$title" -message "$body" -sound default 2>/dev/null || true
    return
  fi

  if command -v osascript &> /dev/null; then
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
    return
  fi

  # Linux
  if command -v notify-send &> /dev/null; then
    notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
    return
  fi

  # WSL - try Windows toast using environment variables (SECURITY: avoids command injection)
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    # Pass values via environment variables to avoid shell/PowerShell injection
    RALPH_TOAST_TITLE="$title" RALPH_TOAST_BODY="$body" powershell.exe -Command '
      $title = $env:RALPH_TOAST_TITLE
      $body = $env:RALPH_TOAST_BODY
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
      $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
      $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
      $text = $xml.GetElementsByTagName("text")
      $text[0].AppendChild($xml.CreateTextNode($title)) | Out-Null
      $text[1].AppendChild($xml.CreateTextNode($body)) | Out-Null
      $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Ralph Wiggum").Show($toast)
    ' 2>/dev/null || true
    return
  fi

  # Fallback: just echo
  echo "🔔 $title: $body" >&2
}

send_notification "$TITLE" "$BODY" "$URGENCY"

exit 0
