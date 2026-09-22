#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# lib/common.sh — Shared helpers for the Grntly Brewer setup toolkit
#
# Source this from every module and from install.sh:
#   source "${GRNTLY_ROOT}/lib/common.sh"
#
# Provides: logging, error handling, sudo keep-alive (with cleanup trap),
# idempotent file edits, dry-run support and small utilities.
# ---------------------------------------------------------------------------

# Guard against double-sourcing.
if [[ -n "${GRNTLY_COMMON_SOURCED:-}" ]]; then
  return 0
fi
GRNTLY_COMMON_SOURCED=1

# --- Global config -----------------------------------------------------------
# DRY_RUN=1 makes run() print instead of execute. Callers/flags may set it.
: "${DRY_RUN:=0}"
: "${GRNTLY_LOG_FILE:=/var/log/grntly-setup.log}"

# --- Colours (only when writing to a TTY) ------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_CYAN=$'\033[1;36m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
fi

# --- Logging -----------------------------------------------------------------
# Every message is timestamped and appended to the log file (best effort) as
# well as printed to the console with a level colour.
_log() {
  local level="$1"; shift
  local colour="$1"; shift
  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[$ts] [$level] $*"
  printf '%s%s%s\n' "$colour" "$line" "$C_RESET"
  # Best-effort file logging; never fail the script because logging failed.
  if [[ -w "$(dirname "$GRNTLY_LOG_FILE")" ]] 2>/dev/null || [[ -w "$GRNTLY_LOG_FILE" ]] 2>/dev/null; then
    printf '%s\n' "$line" >>"$GRNTLY_LOG_FILE" 2>/dev/null || true
  fi
}

log_info()  { _log "INFO"  "$C_CYAN"   "$@"; }
log_ok()    { _log "OK"    "$C_GREEN"  "$@"; }
log_warn()  { _log "WARN"  "$C_YELLOW" "$@"; }
log_error() { _log "ERROR" "$C_RED"    "$@" >&2; }
log_step()  { printf '\n%s=== %s ===%s\n' "$C_CYAN" "$*" "$C_RESET"; }

# --- Run summary -------------------------------------------------------------
# Modules record what they actually did here so the end-of-run summary can make
# any silent "nothing happened" outcome visible.
GRNTLY_SUMMARY=()
summary_add()  { GRNTLY_SUMMARY+=("$*"); }
print_summary() {
  log_step "Samenvatting"
  if [[ ${#GRNTLY_SUMMARY[@]} -eq 0 ]]; then
    log_warn "Er is niets gewijzigd. Controleer of je de juiste keuzes hebt gemaakt."
    return 0
  fi
  local item
  for item in "${GRNTLY_SUMMARY[@]}"; do
    printf '  %s•%s %s\n' "$C_GREEN" "$C_RESET" "$item"
  done
}

# die MESSAGE [EXIT_CODE]
die() {
  log_error "${1:-Fataal fout}"
  exit "${2:-1}"
}

# --- Command execution -------------------------------------------------------
# run CMD ... — execute a command, honouring DRY_RUN and logging it.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

# have CMD — true if command exists on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# require_macos — refuse to run anywhere but macOS.
require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "Dit script is alleen bedoeld voor macOS (Darwin). Gedetecteerd: $(uname -s)."
  fi
}

# require_not_root — the installer expects to be run as the admin user with
# sudo available, NOT as root directly (root breaks user-context steps).
require_not_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Draai dit script niet als root. Draai als een admin-gebruiker; sudo wordt waar nodig gevraagd."
  fi
}

# --- Sudo keep-alive (with guaranteed cleanup) -------------------------------
_SUDO_KEEPALIVE_PID=""

# Kill the keep-alive loop. Registered on EXIT so it can never leak.
sudo_keepalive_stop() {
  if [[ -n "$_SUDO_KEEPALIVE_PID" ]] && kill -0 "$_SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  _SUDO_KEEPALIVE_PID=""
}

# Prime sudo and keep the timestamp fresh until the script exits.
sudo_keepalive_start() {
  [[ "$DRY_RUN" == "1" ]] && return 0
  sudo -v || die "Sudo-rechten zijn vereist."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  _SUDO_KEEPALIVE_PID="$!"
  trap sudo_keepalive_stop EXIT
}

# --- Idempotent file editing -------------------------------------------------
# ensure_line FILE LINE — append LINE to FILE only if it is not already present.
# Creates FILE (and parent dir) if needed. Safe to run repeatedly.
ensure_line() {
  local file="$1" line="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s ensure_line %s <- %q\n' "$C_DIM" "$C_RESET" "$file" "$line"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    printf '%s\n' "$line" >>"$file"
  fi
}

# backup_once FILE — copy FILE to FILE.grntly.bak the first time only.
backup_once() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  [[ -f "${file}.grntly.bak" ]] && return 0
  run cp -p "$file" "${file}.grntly.bak"
}

# --- Prompt helpers ----------------------------------------------------------
# ask_yes_no PROMPT [default] — returns 0 for yes, 1 for no. default: n
ask_yes_no() {
  local prompt="$1" default="${2:-n}" reply
  local hint="[y/N]"; [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint: " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

# read_secret VARNAME PROMPT — read a secret without echoing it. The value is
# stored in the named variable; callers must avoid passing it as a CLI arg.
read_secret() {
  local __var="$1" prompt="$2" __val
  read -r -s -p "$prompt: " __val; echo
  printf -v "$__var" '%s' "$__val"
}

# --- Config (.tsv) helpers ---------------------------------------------------
# tsv_lookup FILE KEY COL — print column COL (1-based) of the first row whose
# first field equals KEY. Lines starting with # are treated as comments.
tsv_lookup() {
  local file="$1" key="$2" col="$3"
  awk -F'\t' -v k="$key" -v c="$col" '
    /^[[:space:]]*#/ { next }
    $1 == k { print $c; found=1; exit }
    END { if (!found) exit 1 }
  ' "$file"
}
