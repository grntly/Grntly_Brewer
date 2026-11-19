#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 55-remote — secure remote administration.
#
# Goal: the admin can connect from their MacBook to any company laptop — wherever
# it is, behind NAT — to run updates, over an encrypted overlay with identity-
# based access control. Raw public-internet SSH is NOT used.
#
#   * Remote Login (sshd) is enabled and hardened to key-only (no passwords,
#     no root), reachable over the Tailscale overlay.
#   * Tailscale (WireGuard) joins the machine to the company tailnet with a
#     tagged auth key; ACLs in the Tailscale admin limit who may reach port 22.
#   * A grntly-update command is installed for the admin to run over SSH.
#
# The Tailscale auth key is a SECRET: it is read from the TS_AUTHKEY env var
# (unattended) or prompted for, and passed to tailscale via a file (never as a
# ps-visible argument). It is never stored in the repo.
# ---------------------------------------------------------------------------

remote_main() {
  if ! ask_yes_no "Remote beheer (SSH via Tailscale) instellen?" "$(policy_default_char ENABLE_REMOTE)"; then
    log_warn "Remote beheer overgeslagen op eigen verzoek."
    return 0
  fi
  _enable_hardened_ssh
  _install_admin_keys
  _setup_tailscale
  _install_update_command
  summary_add "Remote beheer: SSH (key-only) + Tailscale geconfigureerd."
  log_ok "Remote beheer geconfigureerd."
}

# Enable Remote Login and drop in a hardened sshd config (macOS 13+ includes
# /etc/ssh/sshd_config.d/*).
_enable_hardened_ssh() {
  log_info "Remote Login (SSH) inschakelen + hardenen (alleen sleutels)..."
  run sudo systemsetup -setremotelogin on >/dev/null 2>&1 \
    || log_warn "Kon Remote Login niet via systemsetup zetten (controleer Privacy-rechten)."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] /etc/ssh/sshd_config.d/grntly.conf schrijven (key-only, no root)"
    return 0
  fi
  sudo mkdir -p /etc/ssh/sshd_config.d
  sudo tee /etc/ssh/sshd_config.d/grntly.conf >/dev/null <<'SSHD'
# Managed by Grntly Brewer — secure defaults for remote administration.
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
SSHD
  sudo chmod 644 /etc/ssh/sshd_config.d/grntly.conf
}

# Install the admin public key(s) into the admin account's authorized_keys.
_install_admin_keys() {
  local keysfile="${GRNTLY_ROOT}/config.d/ssh_authorized_keys"
  local user="${ADMIN_USERNAME:-$USER}"
  if [[ ! -s "$keysfile" ]] || ! grep -qE '^(ssh-|ecdsa-|sk-)' "$keysfile"; then
    log_warn "Geen publieke sleutels in config.d/ssh_authorized_keys; SSH-sleutel NIET geïnstalleerd."
    log_warn "Vul je beheerders-publieke sleutel in dat bestand en draai: ./install.sh --only 55"
    return 0
  fi
  local home; home="$(user_home "$user")"
  [[ -n "$home" ]] || { log_warn "Home van ${user} niet gevonden; sleutels overslaan."; return 0; }
  log_info "SSH-sleutels installeren voor ${user}..."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] authorized_keys -> ${home}/.ssh/authorized_keys"
    return 0
  fi
  sudo -u "$user" mkdir -p "${home}/.ssh"
  sudo -u "$user" chmod 700 "${home}/.ssh"
  grep -E '^(ssh-|ecdsa-|sk-)' "$keysfile" | sudo -u "$user" tee "${home}/.ssh/authorized_keys" >/dev/null
  sudo -u "$user" chmod 600 "${home}/.ssh/authorized_keys"
  log_ok "SSH-sleutels geïnstalleerd voor ${user}."
}

# Install Tailscale, its system daemon, and bring the machine onto the tailnet.
_setup_tailscale() {
  have brew || { log_warn "Homebrew ontbreekt; Tailscale overgeslagen."; return 0; }
  if ! have tailscale; then
    log_info "Tailscale installeren..."
    run brew install tailscale
  fi

  local tsd; tsd="$(command -v tailscaled 2>/dev/null || echo "/opt/homebrew/bin/tailscaled")"
  run sudo "$tsd" install-system-daemon >/dev/null 2>&1 \
    || log_info "tailscaled system-daemon al aanwezig of niet nodig."

  local host; host="${COMPUTER_NAME:-$(hostname)}"
  local key="${TS_AUTHKEY:-}"
  if [[ -z "$key" ]]; then
    read_secret key "Tailscale auth key (tag:grntly-macs) — leeg = later aanmelden"
  fi
  if [[ -z "$key" ]]; then
    log_warn "Geen Tailscale auth key opgegeven. Meld later aan met:"
    log_warn "  sudo tailscale up --ssh --hostname ${host}"
    return 0
  fi

  log_info "Tailscale aanmelden als ${host}..."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] sudo tailscale up --authkey file:<tmp> --hostname ${host} --ssh"
    return 0
  fi
  # Pass the key via a 0600 temp file so it is never visible in the process list.
  local tmpkey; tmpkey="$(mktemp)"; chmod 600 "$tmpkey"; printf '%s' "$key" >"$tmpkey"
  sudo tailscale up --authkey "file:${tmpkey}" --hostname "$host" --accept-dns=false --ssh \
    || sudo tailscale up --authkey "file:${tmpkey}" --hostname "$host" --accept-dns=false \
    || log_warn "tailscale up mislukt; controleer de auth key en tag."
  rm -f "$tmpkey"
}

# Install the remote update command the admin invokes over SSH.
_install_update_command() {
  local src="${GRNTLY_ROOT}/agent/grntly-update.sh"
  [[ -f "$src" ]] || return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] install ${src} -> /usr/local/grntly/grntly-update.sh"
    return 0
  fi
  sudo mkdir -p /usr/local/grntly
  sudo install -m 0755 "$src" /usr/local/grntly/grntly-update.sh
  log_info "Remote update: ssh ${ADMIN_USERNAME:-admin}@<host> 'sudo /usr/local/grntly/grntly-update.sh'"
}
