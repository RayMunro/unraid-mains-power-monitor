#!/bin/bash
set -u

NAME="mains-power-monitor"
CFGDIR="/boot/config/plugins/${NAME}"
CFG="${CFGDIR}/${NAME}.cfg"
PENDING_FILE="${CFGDIR}/pending-outage"
LAST_FILE="${CFGDIR}/last-outage"
STATE_DIR="/var/local/${NAME}"
STATE_FILE="${STATE_DIR}/state"
PID_FILE="/var/run/${NAME}.pid"
NOTIFY="/usr/local/emhttp/webGui/scripts/notify"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)"
MONITOR_START_EPOCH="$(date +%s)"
MONITOR_START_TEXT="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$STATE_DIR" "$CFGDIR"
log() { logger -t "$NAME" -- "$*"; }

load_cfg() {
  ENABLED="no"; TARGET_IP=""; CHECK_INTERVAL="5"; PING_TIMEOUT="2"; FAIL_THRESHOLD="4"; RECOVERY_THRESHOLD="2"
  [[ -f "$CFG" ]] && source "$CFG"
}

write_state() {
  local status="$1" detail="$2" now
  now="$(date '+%Y-%m-%d %H:%M:%S')"
  umask 022
  { printf 'STATUS="%s"\n' "$status"; printf 'DETAIL="%s"\n' "$detail"; printf 'UPDATED="%s"\n' "$now"; printf 'TARGET_IP="%s"\n' "$TARGET_IP"; } > "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
}

send_warning() {
  local subject="$1" description="$2"
  [[ -x "$NOTIFY" ]] || { log "Notification script not found: $NOTIFY"; return 1; }
  "$NOTIFY" -e "Unraid Mains Power Monitor" -s "$subject" -d "$description" -i "warning" >/dev/null 2>&1
}

format_duration() {
  local total="$1" d h m s out=""
  (( total < 0 )) && total=0
  d=$((total/86400)); total=$((total%86400)); h=$((total/3600)); total=$((total%3600)); m=$((total/60)); s=$((total%60))
  (( d > 0 )) && out+="${d}d "; (( h > 0 || d > 0 )) && out+="${h}h "; (( m > 0 || h > 0 || d > 0 )) && out+="${m}m "; out+="${s}s"
  printf '%s' "$out"
}

write_pending() {
  local start_epoch="$1" start_text="$2"
  umask 022
  {
    printf 'START_EPOCH="%s"\n' "$start_epoch"
    printf 'START_TEXT="%s"\n' "$start_text"
    printf 'TARGET_IP="%s"\n' "$TARGET_IP"
    printf 'DETECTED_BOOT_ID="%s"\n' "$BOOT_ID"
    printf 'SHUTDOWN_EPOCH=""\n'
    printf 'SHUTDOWN_TEXT=""\n'
  } > "${PENDING_FILE}.tmp"
  mv -f "${PENDING_FILE}.tmp" "$PENDING_FILE"
}

load_pending() {
  START_EPOCH=""; START_TEXT=""; DETECTED_BOOT_ID=""; SHUTDOWN_EPOCH=""; SHUTDOWN_TEXT=""
  if [[ -f "$PENDING_FILE" ]]; then
    source "$PENDING_FILE"
    [[ -n "${START_EPOCH:-}" && -n "${START_TEXT:-}" ]]
    return $?
  fi
  return 1
}

write_last() {
  local end_epoch="$1" end_text="$2" duration="$3" rebooted="$4" restart_text="$5"
  umask 022
  {
    printf 'START_EPOCH="%s"\n' "$START_EPOCH"; printf 'START_TEXT="%s"\n' "$START_TEXT"
    printf 'SHUTDOWN_EPOCH="%s"\n' "${SHUTDOWN_EPOCH:-}"; printf 'SHUTDOWN_TEXT="%s"\n' "${SHUTDOWN_TEXT:-}"
    printf 'REBOOTED="%s"\n' "$rebooted"; printf 'RESTART_TEXT="%s"\n' "$restart_text"
    printf 'END_EPOCH="%s"\n' "$end_epoch"; printf 'END_TEXT="%s"\n' "$end_text"; printf 'DURATION="%s"\n' "$duration"
    printf 'TARGET_IP="%s"\n' "$TARGET_IP"
  } > "${LAST_FILE}.tmp"
  mv -f "${LAST_FILE}.tmp" "$LAST_FILE"
}

cleanup(){ rm -f "$PID_FILE"; }
trap cleanup EXIT
trap 'exit 0' INT TERM

load_cfg
[[ "$ENABLED" == "yes" ]] || { write_state "DISABLED" "Monitoring is disabled"; exit 0; }
[[ -n "$TARGET_IP" ]] || { write_state "ERROR" "No target IP configured"; log "No target IP configured"; exit 1; }
printf '%s\n' "$$" > "$PID_FILE"

if load_pending; then
  current="OFFLINE"
  if [[ -n "${DETECTED_BOOT_ID:-}" && "$DETECTED_BOOT_ID" != "$BOOT_ID" ]]; then
    write_state "RECOVERING" "A pending outage survived an Unraid shutdown/reboot; waiting for the monitored network device/network"
    log "Pending outage from $START_TEXT survived reboot; current boot=$BOOT_ID"
  else
    write_state "OFFLINE" "A mains/network outage is already recorded from $START_TEXT; waiting for the monitored network device to return"
    log "Resuming pending outage recorded at $START_TEXT"
  fi
else
  current="UNKNOWN"
  write_state "STARTING" "Waiting for first confirmed state"
fi

fail_count=0; success_count=0; candidate_start_epoch=""; candidate_start_text=""

while true; do
  load_cfg
  [[ "$ENABLED" == "yes" ]] || { write_state "DISABLED" "Monitoring was disabled"; exit 0; }

  if ping -n -c 1 -W "$PING_TIMEOUT" "$TARGET_IP" >/dev/null 2>&1; then
    fail_count=0; candidate_start_epoch=""; candidate_start_text=""; success_count=$((success_count+1))

    if [[ "$current" == "OFFLINE" && "$success_count" -ge "$RECOVERY_THRESHOLD" ]]; then
      if load_pending; then
        end_epoch="$(date +%s)"; end_text="$(date '+%Y-%m-%d %H:%M:%S')"; duration_seconds=$((end_epoch-START_EPOCH)); duration_text="$(format_duration "$duration_seconds")"
        rebooted="no"; restart_text=""
        [[ -n "${DETECTED_BOOT_ID:-}" && "$DETECTED_BOOT_ID" != "$BOOT_ID" ]] && { rebooted="yes"; restart_text="$MONITOR_START_TEXT"; }

        if [[ "$rebooted" == "yes" ]]; then
          description="Mains/network loss was detected at $START_TEXT."
          [[ -n "${SHUTDOWN_TEXT:-}" ]] && description+=" Unraid stopped/shut down at $SHUTDOWN_TEXT while the outage was pending."
          description+=" Unraid started again at approximately $restart_text, and the monitored network device/network was confirmed reachable at $end_text. Time from detected loss until connectivity was confirmed again: $duration_text. Because Unraid was offline for part of this event, the exact mains-restoration time cannot be known."
          subject="Mains Power Restored - Unraid Restarted"
        else
          description="Mains/network loss was detected at $START_TEXT and the monitored network device/network was confirmed reachable again at $end_text. Detected outage duration: $duration_text."
          subject="Mains Power Restored - Outage Recorded"
        fi

        write_state "RECOVERED" "Connectivity restored; sending Warning notification ($duration_text)"
        if send_warning "$subject" "$description"; then
          write_last "$end_epoch" "$end_text" "$duration_text" "$rebooted" "$restart_text"
          rm -f "$PENDING_FILE"
          current="ONLINE"
          write_state "ONLINE" "Mains/network restored; Warning notification sent; last detected outage lasted $duration_text"
          log "Warning recovery report sent; start=$START_TEXT end=$end_text duration=$duration_text rebooted=$rebooted"
        else
          write_state "RECOVERED" "Connectivity restored, but Warning notification could not be queued; retrying"
          log "Warning notification command failed after recovery; pending outage retained"
        fi
      else
        current="ONLINE"; write_state "ONLINE" "Monitored network device is reachable; no pending outage record found"
      fi
    elif [[ "$current" == "UNKNOWN" && "$success_count" -ge "$RECOVERY_THRESHOLD" ]]; then
      current="ONLINE"; write_state "ONLINE" "Mains/network present; monitored network device is reachable"; log "Initial state confirmed online"
    elif [[ "$current" == "ONLINE" ]]; then
      write_state "ONLINE" "Mains/network present; monitored network device is reachable"
    fi
  else
    success_count=0; fail_count=$((fail_count+1))
    if [[ -z "$candidate_start_epoch" ]]; then candidate_start_epoch="$(date +%s)"; candidate_start_text="$(date '+%Y-%m-%d %H:%M:%S')"; fi
    if [[ "$current" != "OFFLINE" && "$fail_count" -ge "$FAIL_THRESHOLD" ]]; then
      current="OFFLINE"; write_pending "$candidate_start_epoch" "$candidate_start_text"
      write_state "SHUTTING_DOWN" "Mains/network loss confirmed at $candidate_start_text after $fail_count failed checks; initiating clean Unraid shutdown"
      log "Target unreachable for $fail_count checks; outage persisted from $candidate_start_text; initiating clean shutdown"

      # The mains-powered LAN is already unavailable, so a phone notification may not be deliverable now.
      # Persist first, then ask Unraid to perform its native clean shutdown. The stopping_svcs event
      # stamps the pending record, and the next boot sends the Warning recovery report once networking returns.
      if command -v powerdown >/dev/null 2>&1; then
        nohup powerdown >/dev/null 2>&1 &
      elif [[ -x /usr/local/sbin/powerdown ]]; then
        nohup /usr/local/sbin/powerdown >/dev/null 2>&1 &
      else
        write_state "ERROR" "Mains/network loss confirmed, but Unraid powerdown command was not found"
        log "ERROR: powerdown command not found; clean shutdown could not be initiated"
        exit 1
      fi
      exit 0
    elif [[ "$current" == "ONLINE" ]]; then
      write_state "ONLINE" "Transient ping failure (${fail_count}/${FAIL_THRESHOLD}); outage not yet declared"
    elif [[ "$current" == "OFFLINE" ]]; then
      load_pending && write_state "OFFLINE" "Mains/network outage remains active; recorded from $START_TEXT"
    else
      write_state "STARTING" "Waiting for confirmation (${fail_count}/${FAIL_THRESHOLD} failed checks)"
    fi
  fi
  sleep "$CHECK_INTERVAL"
done
