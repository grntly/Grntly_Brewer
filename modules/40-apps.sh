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

_set_wallpaper() {
  [[ -n "${WALLPAPER_URL:-}" ]] || return 0
  local dest="/Library/Desktop Pictures/company-wallpaper.jpg"
  log_info "Wallpaper downloaden..."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] wallpaper -> $dest"
    return 0
  fi
  run sudo mkdir -p "/Library/Desktop Pictures"
  if curl -fsSL --max-time 30 "$WALLPAPER_URL" -o /tmp/company-wallpaper.jpg; then
    sudo cp /tmp/company-wallpaper.jpg "$dest"
    rm -f /tmp/company-wallpaper.jpg
    osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$dest\"" 2>/dev/null || true
    log_ok "Wallpaper geïnstalleerd."
  else
    log_warn "Wallpaper downloaden mislukt voor ${COMPANY_NAME}."
  fi
}

_reset_dock() {
  have dockutil || _install_pkg formula dockutil
  if have dockutil; then
    log_info "Dock opschonen..."
    run dockutil --remove all --no-restart 2>/dev/null || true
  fi
}

apps_main() {
  _ensure_brew

  log_info "App-profiel installeren voor: ${USER_TYPE}"
  _install_profile "$USER_TYPE"

  _set_wallpaper
  _reset_dock

  # A sensible default Dock for everyone; the developer module adds dev tools.
  if have dockutil; then
    run dockutil --add "/Applications/Google Chrome.app" --no-restart 2>/dev/null || true
    run dockutil --add "/Applications/Slack.app" --no-restart 2>/dev/null || true
    run dockutil --add "/System/Applications/Mail.app" --no-restart 2>/dev/null || true
    run dockutil --add "/System/Applications/Notes.app" --no-restart 2>/dev/null || true
    # Web-app shortcuts (e.g. Google Sheets/Docs/Slides) as a Dock folder.
    if [[ -d "$WEBAPP_DIR" ]]; then
      run dockutil --add "$WEBAPP_DIR" --view grid --display folder --no-restart 2>/dev/null || true
    fi
    run killall Dock 2>/dev/null || true
  fi

  log_ok "Apps geïnstalleerd voor ${USER_TYPE}."
  summary_add "Apps voor ${USER_TYPE}: ${GRNTLY_APP_COUNT} nieuw geïnstalleerd (rest was al aanwezig)"
}
