#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 40-apps — install the app profile for the selected USER_TYPE, plus the
# company wallpaper and a cleaned-up Dock. App lists are data-driven from
# config.d/apps.tsv (no hardcoded case blocks).
# ---------------------------------------------------------------------------

# Web-app shortcuts (for services without a native app/cask, e.g. Google Sheets)
# are placed here as .webloc files and this folder is added to the Dock.
WEBAPP_DIR="/Applications/Grntly Web Apps"

# Counter of packages/shortcuts actually installed this run.
GRNTLY_APP_COUNT=0

# _ensure_brew — make sure brew is on PATH; recover from a missing shellenv,
# and fail LOUDLY rather than silently skipping every app.
_ensure_brew() {
  have brew && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then eval "$("$b" shellenv)"; break; fi
  done
  have brew || die "Homebrew is niet beschikbaar; kan geen apps installeren. Draai eerst module 30: ./install.sh --only 30"
}

# _install_pkg formula|cask|webapp NAME [URL]
_install_pkg() {
  local kind="$1" name="$2" url="${3:-}"
  case "$kind" in
    formula)
      if brew list --versions "$name" &>/dev/null; then
        log_info "$name is al geïnstalleerd."
      else
        run brew install "$name" && GRNTLY_APP_COUNT=$((GRNTLY_APP_COUNT + 1))
      fi ;;
    cask)
      if brew list --cask --versions "$name" &>/dev/null; then
        log_info "$name (cask) is al geïnstalleerd."
      else
        run brew install --cask "$name" && GRNTLY_APP_COUNT=$((GRNTLY_APP_COUNT + 1))
      fi ;;
    webapp)
      _install_webapp "$name" "$url" && GRNTLY_APP_COUNT=$((GRNTLY_APP_COUNT + 1)) ;;
  esac
}

# _install_webapp NAME URL — create a .webloc web-app shortcut (idempotent).
_install_webapp() {
  local name="$1" url="$2"
  [[ -n "$url" ]] || { log_warn "Webapp '$name' zonder URL; overslaan."; return 0; }
  local file="${WEBAPP_DIR}/${name}.webloc"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] web-app snelkoppeling ${file} -> ${url}"
    return 0
  fi
  sudo mkdir -p "$WEBAPP_DIR"
  sudo tee "$file" >/dev/null <<WEBLOC
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>${url}</string>
</dict>
</plist>
WEBLOC
  log_ok "Web-app snelkoppeling: ${name} (${url})"
}

_install_profile() {
  local role="$1" cfg="${GRNTLY_ROOT}/config.d/apps.tsv"
  # Read rows matching the role: field2=kind, field3=name, field4=url (webapp).
  local r kind name url
  while IFS=$'\t' read -r r kind name url; do
    [[ "$r" == "$role" ]] || continue
    [[ -n "$name" ]] || continue
    _install_pkg "$kind" "$name" "$url"
  done < <(awk -F'\t' '/^[[:space:]]*#/{next} NF>=3' "$cfg")
}

WALLPAPER_DEST="/Library/Desktop Pictures/company-wallpaper.jpg"
WALLPAPER_AGENT="/Library/LaunchAgents/com.grntly.wallpaper.plist"
WALLPAPER_SCRIPT="/usr/local/grntly/set-wallpaper.sh"

# _deploy_wallpaper — install the company wallpaper system-wide and apply it to
# every user, including accounts that have not logged in yet. A per-login
# LaunchAgent sets it in each user's GUI session (osascript needs an Aqua
# session, so it cannot be set directly for a not-logged-in user).
_deploy_wallpaper() {
  [[ -n "${WALLPAPER_URL:-}" ]] || return 0
  log_info "Wallpaper installeren (systeembreed, alle gebruikers)..."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] download ${WALLPAPER_URL} -> ${WALLPAPER_DEST}; LaunchAgent ${WALLPAPER_AGENT}"
    return 0
  fi

  sudo mkdir -p "/Library/Desktop Pictures"
  if ! curl -fsSL --max-time 30 "$WALLPAPER_URL" -o /tmp/company-wallpaper.jpg; then
    log_warn "Wallpaper downloaden mislukt voor ${COMPANY_NAME}; overslaan."
    return 0
  fi
  sudo cp /tmp/company-wallpaper.jpg "$WALLPAPER_DEST"
  sudo chmod 644 "$WALLPAPER_DEST"
  rm -f /tmp/company-wallpaper.jpg

  sudo mkdir -p /usr/local/grntly
  sudo tee "$WALLPAPER_SCRIPT" >/dev/null <<'WP'
#!/bin/bash
IMG="/Library/Desktop Pictures/company-wallpaper.jpg"
[[ -f "$IMG" ]] || exit 0
osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$IMG\"" 2>/dev/null || true
WP
  sudo chmod 755 "$WALLPAPER_SCRIPT"

  sudo tee "$WALLPAPER_AGENT" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.grntly.wallpaper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${WALLPAPER_SCRIPT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST
  sudo chmod 644 "$WALLPAPER_AGENT"

  # Apply immediately for whoever is at the console right now (if anyone).
  local console_user; console_user="$(stat -f%Su /dev/console 2>/dev/null || echo '')"
  if [[ -n "$console_user" && "$console_user" != "root" ]]; then
    run_as "$console_user" osascript -e \
      "tell application \"System Events\" to set picture of every desktop to POSIX file \"$WALLPAPER_DEST\"" \
      2>/dev/null || true
  fi
  log_ok "Wallpaper geïnstalleerd + LaunchAgent voor toekomstige logins."
  summary_add "Wallpaper ingesteld voor alle gebruikers (${COMPANY_NAME})"
}

# _configure_dock — apply the standard Dock to EVERY human user's own Dock,
# not just the admin running the installer. dockutil runs as each user so the
# plist keeps correct ownership.
_configure_dock() {
  local du; du="$(dock_bin)"
  [[ -n "$du" ]] || { log_warn "dockutil niet beschikbaar; Dock niet aangepast."; return 0; }
  local u
  while read -r u; do
    [[ -n "$u" ]] && _configure_dock_for_user "$u" "$du"
  done < <(human_users)
}

_configure_dock_for_user() {
  local user="$1" du="$2" home
  home="$(user_home "$user")"
  [[ -d "$home" ]] || return 0
  log_info "Dock instellen voor ${user}"
  run_as "$user" "$du" --remove all --no-restart "$home" >/dev/null 2>&1 || true
  local app
  for app in "/Applications/Google Chrome.app" \
             "/Applications/Slack.app" \
             "/System/Applications/Mail.app" \
             "/System/Applications/Notes.app"; do
    if [[ -e "$app" ]]; then
      run_as "$user" "$du" --add "$app" --no-restart "$home" >/dev/null 2>&1 || true
    fi
  done
  if [[ -d "$WEBAPP_DIR" ]]; then
    run_as "$user" "$du" --add "$WEBAPP_DIR" --view grid --display folder --no-restart "$home" >/dev/null 2>&1 || true
  fi
  run_as "$user" killall Dock >/dev/null 2>&1 || true
}

apps_main() {
  _ensure_brew

  log_info "App-profiel installeren voor: ${USER_TYPE}"
  _install_profile "$USER_TYPE"

  _deploy_wallpaper
  _configure_dock

  log_ok "Apps geïnstalleerd voor ${USER_TYPE}."
  summary_add "Apps voor ${USER_TYPE}: ${GRNTLY_APP_COUNT} nieuw geïnstalleerd (rest was al aanwezig)"
}
