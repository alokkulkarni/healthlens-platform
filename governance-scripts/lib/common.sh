#!/usr/bin/env bash
# lib/common.sh — Shared utilities for all governance scripts
# Source this file at the top of each script: source "$(dirname "$0")/../lib/common.sh"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Output helpers ────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️${NC}  $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}── $* ${NC}"; }
header()  { echo -e "\n${BOLD}${MAGENTA}╔══════════════════════════════════════════╗${NC}"; \
            echo -e "${BOLD}${MAGENTA}║  $*${NC}"; \
            echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════╝${NC}\n"; }
divider() { echo -e "${DIM}────────────────────────────────────────────────────${NC}"; }

# ── Interactive prompts ───────────────────────────────────────────────────────

# required_input "prompt text" VAR_NAME
required_input() {
  local prompt="$1"
  local var_name="$2"
  local value=""
  while [[ -z "$value" ]]; do
    read -rp "$(echo -e "${CYAN}  ✦ ${BOLD}${prompt}${NC}: ")" value
    [[ -z "$value" ]] && warn "  This field is required."
  done
  printf -v "$var_name" '%s' "$value"
}

# optional_input "prompt text" VAR_NAME "default value"
optional_input() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"
  local value=""
  local display_default=""
  [[ -n "$default" ]] && display_default=" (default: ${DIM}${default}${NC})"
  read -rp "$(echo -e "${CYAN}  ○ ${prompt}${display_default}: ")" value
  printf -v "$var_name" '%s' "${value:-$default}"
}

# confirm "question" → returns 0 for yes, 1 for no
confirm() {
  local prompt="${1:-Continue?}"
  local response
  while true; do
    read -rp "$(echo -e "${YELLOW}  ? ${BOLD}${prompt}${NC} [y/N]: ")" response
    case "$response" in
      [Yy]*) return 0 ;;
      [Nn]*|"") return 1 ;;
      *) warn "  Please answer y or n." ;;
    esac
  done
}

# multi_select "prompt" "option1|option2|option3" VAR_NAME
# Displays numbered options, user enters comma-separated numbers
multi_select() {
  local prompt="$1"
  IFS='|' read -ra options <<< "$2"
  local var_name="$3"
  local selected=""

  echo -e "${CYAN}  ✦ ${BOLD}${prompt}${NC}:"
  for i in "${!options[@]}"; do
    echo -e "    ${DIM}$((i+1))${NC}. ${options[$i]}"
  done
  read -rp "$(echo -e "${CYAN}    Enter numbers (comma-separated, e.g. 1,3): ")" selected
  printf -v "$var_name" '%s' "$selected"
}

# ── GitHub API helpers ────────────────────────────────────────────────────────

# push_file ORG REPO FILE_PATH "content" "commit message" [branch]
push_file() {
  local org="$1"
  local repo="$2"
  local file_path="$3"
  local content="$4"
  local commit_msg="$5"
  local branch="${6:-main}"

  local encoded
  encoded=$(printf '%s' "$content" | base64 | tr -d '\n')

  # Check if file already exists (need SHA to update)
  local existing_sha
  existing_sha=$(gh api "/repos/$org/$repo/contents/$file_path" \
    --jq '.sha' 2>/dev/null || echo "")

  local payload
  if [[ -n "$existing_sha" ]]; then
    payload=$(jq -n \
      --arg msg "$commit_msg" \
      --arg content "$encoded" \
      --arg sha "$existing_sha" \
      --arg branch "$branch" \
      '{message: $msg, content: $content, sha: $sha, branch: $branch}')
  else
    payload=$(jq -n \
      --arg msg "$commit_msg" \
      --arg content "$encoded" \
      --arg branch "$branch" \
      '{message: $msg, content: $content, branch: $branch}')
  fi

  if gh api --method PUT "/repos/$org/$repo/contents/$file_path" \
       --input - <<< "$payload" &>/dev/null; then
    success "  Pushed: $file_path"
  else
    error "  Failed to push: $file_path"
    return 1
  fi
}

# create_label ORG REPO "label-name" "colour-hex" "description"
create_label() {
  local org="$1"
  local repo="$2"
  local name="$3"
  local color="$4"
  local description="$5"

  # Delete if exists, then recreate (idempotent)
  gh api --method DELETE "/repos/$org/$repo/labels/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))" 2>/dev/null || echo "$name")" &>/dev/null || true

  if gh api --method POST "/repos/$org/$repo/labels" \
       --field name="$name" \
       --field color="$color" \
       --field description="$description" &>/dev/null; then
    success "  Label: $name"
  else
    warn "  Label may already exist: $name"
  fi
}

# org_api ORG ENDPOINT [extra gh api args]
org_api() {
  local org="$1"
  shift
  gh api --method PATCH "/orgs/$org" "$@"
}

# ── Prerequisites check ───────────────────────────────────────────────────────
check_prereqs() {
  step "Checking prerequisites"
  local missing=0

  for cmd in gh jq base64; do
    if command -v "$cmd" &>/dev/null; then
      success "  Found: $cmd"
    else
      error "  Missing: $cmd"
      missing=1
    fi
  done

  if [[ $missing -eq 1 ]]; then
    echo ""
    info "Install missing tools:"
    echo "  gh:      https://cli.github.com/"
    echo "  jq:      brew install jq"
    echo "  base64:  included in macOS/Linux coreutils"
    exit 1
  fi

  if gh auth status &>/dev/null; then
    local user
    user=$(gh api /user --jq '.login' 2>/dev/null)
    success "  Authenticated as: $user"
  else
    error "  GitHub CLI not authenticated. Run: gh auth login"
    exit 1
  fi
}

# ── Config persistence ────────────────────────────────────────────────────────
# Store and load config so setup scripts share values

CONFIG_FILE="${GOVERNANCE_CONFIG:-$HOME/.github-governance-setup.env}"

save_config() {
  local key="$1"
  local value="$2"
  # Remove existing key, then append
  grep -v "^${key}=" "$CONFIG_FILE" 2>/dev/null > "${CONFIG_FILE}.tmp" || true
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" 2>/dev/null || touch "$CONFIG_FILE"
  echo "${key}=${value}" >> "$CONFIG_FILE"
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    set -a; source "$CONFIG_FILE"; set +a
  fi
}

# ── Repo existence check ──────────────────────────────────────────────────────
repo_exists() {
  local org="$1"
  local repo="$2"
  gh api "/repos/$org/$repo" &>/dev/null
}

team_exists() {
  local org="$1"
  local team="$2"
  gh api "/orgs/$org/teams/$team" &>/dev/null
}
