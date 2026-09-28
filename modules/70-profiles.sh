#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 70-profiles — deploy macOS defaults and managed shell profiles to EVERY
# human user, not just the admin running the installer. Idempotent.
#
# Per user:
#   * an optimal set of macOS defaults (Finder/Dock/screenshots/…), applied
#     with `sudo -u <user> defaults write` so each account gets them;
#   * a managed .bashrc (from profiles/bashrc.template) + .bash_profile;
#   * a .zprofile that puts Homebrew on PATH (zsh is the macOS default shell);
#   * a ~/Development directory.
# ---------------------------------------------------------------------------

profiles_main() {
  local u count=0
  while read -r u; do
    [[ -n "$u" ]] || continue
    log_info "Profiel toepassen voor gebruiker: ${u}"
    _apply_macos_defaults_for "$u"
    _deploy_dotfiles_one "$u"
    count=$((count + 1))
  done < <(human_users)
  summary_add "Profielen (Finder/Dock-defaults + dotfiles) uitgerold voor ${count} gebruiker(s)"
  log_ok "Profielen uitgerold."
}

# --- macOS defaults (per user) ----------------------------------------------
_apply_macos_defaults_for() {
  local user="$1" home
  home="$(user_home "$user")"

  # Finder: path/status bar, show extensions, POSIX path in title
  run_as "$user" defaults write com.apple.finder ShowPathbar -bool true
  run_as "$user" defaults write com.apple.finder ShowStatusBar -bool true
  run_as "$user" defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  run_as "$user" defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  run_as "$user" defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

  # Screenshots to ~/Screenshots as PNG
  if [[ -n "$home" ]]; then
    run_as "$user" mkdir -p "${home}/Screenshots"
    run_as "$user" defaults write com.apple.screencapture location -string "${home}/Screenshots"
  fi
  run_as "$user" defaults write com.apple.screencapture type -string "png"

  # Dock: autohide, no recents
  run_as "$user" defaults write com.apple.dock autohide -bool true
  run_as "$user" defaults write com.apple.dock show-recents -bool false

  # Avoid .DS_Store on network/USB volumes
  run_as "$user" defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  run_as "$user" defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

  # Expand save/print dialogs by default
  run_as "$user" defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  run_as "$user" defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

  # Restart the UI for this user if they are logged in (harmless otherwise).
  run_as "$user" killall Finder >/dev/null 2>&1 || true
  run_as "$user" killall Dock   >/dev/null 2>&1 || true
}

# --- Dotfiles (per user) ----------------------------------------------------
_deploy_dotfiles_one() {
  local user="$1" home tmpl="${GRNTLY_ROOT}/profiles/bashrc.template"
  home="$(user_home "$user")"
  [[ -d "$home" ]] || { log_warn "Home van ${user} niet gevonden; dotfiles overslaan."; return 0; }

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] dotfiles (.bashrc/.bash_profile/.zprofile) + ~/Development voor ${user}"
    return 0
  fi

  # Back up existing files once (sudo: we may be writing another user's home).
  local f
  for f in .bashrc .zprofile; do
    if [[ -f "${home}/${f}" && ! -f "${home}/${f}.grntly.bak" ]]; then
      sudo cp -p "${home}/${f}" "${home}/${f}.grntly.bak"
    fi
  done

  sudo cp "$tmpl" "${home}/.bashrc"
  printf '%s\n' '[[ -f ~/.bashrc ]] && source ~/.bashrc' | sudo tee "${home}/.bash_profile" >/dev/null

  # zsh (macOS default shell): put Homebrew on PATH for login shells.
  sudo tee "${home}/.zprofile" >/dev/null <<'ZP'
# Managed by Grntly Brewer
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
ZP

  sudo mkdir -p "${home}/Development"
  sudo chown "$user" \
    "${home}/.bashrc" "${home}/.bash_profile" "${home}/.zprofile" "${home}/Development"
}
