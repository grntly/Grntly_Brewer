#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 80-developer — developer-only tooling. Runs only for USER_TYPE=Developer.
#
# Local container development uses OrbStack ("orb local") instead of Docker
# Desktop: it ships the `docker`, `docker compose` and `orb` CLIs, is fast on
# Apple Silicon and avoids Docker Desktop's commercial licensing.
# ---------------------------------------------------------------------------

developer_main() {
  if [[ "${USER_TYPE:-}" != "Developer" ]]; then
    log_info "Geen developer-machine; developer-module overgeslagen."
    return 0
  fi
  have brew || { log_warn "Homebrew ontbreekt; developer-setup overgeslagen."; return 0; }

  _ensure_orbstack
  _vscode_extensions
  _dev_dock
  log_ok "Developer-omgeving klaar (OrbStack + tooling)."
}

_ensure_orbstack() {
  if brew list --cask --versions orbstack &>/dev/null; then
    log_info "OrbStack is al geïnstalleerd."
  else
    log_info "OrbStack installeren (docker + orb CLI)..."
    run brew install --cask orbstack
  fi
  # First launch registers the docker/orb CLIs and the Linux VM.
  run open -ga OrbStack 2>/dev/null || true
  if have docker; then
    log_info "docker CLI beschikbaar via OrbStack."
  else
    log_warn "docker CLI nog niet op PATH; start OrbStack eenmalig handmatig af."
  fi
}

_vscode_extensions() {
  have code || { log_info "VS Code CLI niet gevonden; extensies overgeslagen."; return 0; }
  local ext
  for ext in esbenp.prettier-vscode dbaeumer.vscode-eslint \
             ms-azuretools.vscode-docker github.copilot; do
    run code --install-extension "$ext" --force 2>/dev/null || \
      log_warn "VS Code extensie $ext kon niet worden geïnstalleerd."
  done
}

_dev_dock() {
  local du; du="$(dock_bin)"
  [[ -n "$du" ]] || return 0
  local u home app
  while read -r u; do
    [[ -n "$u" ]] || continue
    home="$(user_home "$u")"
    [[ -d "$home" ]] || continue
    for app in "/Applications/Visual Studio Code.app" \
               "/Applications/OrbStack.app" \
               "/Applications/Postman.app" \
               "/System/Applications/Utilities/Terminal.app"; do
      if [[ -e "$app" ]]; then
        run_as "$u" "$du" --add "$app" --no-restart "$home" >/dev/null 2>&1 || true
      fi
    done
    run_as "$u" killall Dock >/dev/null 2>&1 || true
  done < <(human_users)
}
