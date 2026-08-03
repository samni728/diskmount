#!/bin/zsh

set -u

SELF_PATH="${0:A}"
VOLUME_UUID="6CDEB437-5859-48D2-BFF6-E18A0CB190D1"
VOLUME_NAME="Internal256"
EXPECTED_MOUNT_POINT="/Volumes/Internal256"
LABEL="com.samni.automount.internal256"
SCRIPT_PATH="$HOME/Library/Scripts/AutoMount-Internal256.zsh"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs"
OUT_LOG="${LOG_DIR}/AutoMount-Internal256.log"
ERR_LOG="${LOG_DIR}/AutoMount-Internal256.err.log"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  mkdir -p "$LOG_DIR"
  print "[$(timestamp)] $*" | tee -a "$OUT_LOG"
}

mounted_now() {
  diskutil info "$VOLUME_UUID" 2>/dev/null | awk -F': *' '/Mount Point/ { print $2; exit }'
}

mount_once() {
  local mount_point
  mount_point="$(mounted_now)"

  if [[ -n "$mount_point" && "$mount_point" != "Not Mounted" ]]; then
    log "${VOLUME_NAME} is already mounted at ${mount_point}"
    return 0
  fi

  if ! diskutil info "$VOLUME_UUID" >/dev/null 2>&1; then
    log "${VOLUME_NAME} (${VOLUME_UUID}) was not found; will check again later"
    return 0
  fi

  log "Mounting ${VOLUME_NAME}..."
  if /usr/sbin/diskutil mount "$VOLUME_UUID" >>"$OUT_LOG" 2>>"$ERR_LOG"; then
    mount_point="$(mounted_now)"
    log "Mounted: ${mount_point:-$EXPECTED_MOUNT_POINT}"
    return 0
  fi

  log "Mount failed; see ${ERR_LOG}"
  return 1
}

install_agent() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Scripts" "$LOG_DIR"
  /bin/cp "$SELF_PATH" "$SCRIPT_PATH"
  chmod 755 "$SCRIPT_PATH"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${SCRIPT_PATH}</string>
    <string>--mount-once</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>30</integer>

  <key>StandardOutPath</key>
  <string>${OUT_LOG}</string>

  <key>StandardErrorPath</key>
  <string>${ERR_LOG}</string>
</dict>
</plist>
PLIST

  chmod 644 "$PLIST_PATH"

  /bin/launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
  /bin/launchctl enable "gui/$(id -u)/${LABEL}"
  /bin/launchctl kickstart -k "gui/$(id -u)/${LABEL}"

  log "Auto mount is installed: run at login and check every 30 seconds"
  log "LaunchAgent: ${PLIST_PATH}"
  log "Log: ${OUT_LOG}"
}

uninstall_agent() {
  /bin/launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
  rm -f "$PLIST_PATH"
  log "Auto mount has been removed"
}

case "${1:-}" in
  --mount-once)
    mount_once
    ;;
  --install|"")
    install_agent
    mount_once
    print ""
    print "Done. ${VOLUME_NAME} will mount after login and will be checked every 30 seconds."
    print "You can close this window."
    ;;
  --uninstall)
    uninstall_agent
    print ""
    print "Auto mount has been disabled for ${VOLUME_NAME}."
    ;;
  *)
    print "Usage:"
    print "  Double click: install auto mount"
    print "  $0 --mount-once: mount once"
    print "  $0 --uninstall: disable auto mount"
    exit 2
    ;;
esac
