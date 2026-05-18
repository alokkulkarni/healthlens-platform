#!/usr/bin/env bash
# reports/admin-report.sh — Pull current admin access and recent admin changes
# Usage: bash reports/admin-report.sh [--org my-org] [--enterprise my-enterprise]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)        GITHUB_ORG="$2";        shift 2 ;;
    --enterprise) GITHUB_ENTERPRISE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

check_prereqs
: "${GITHUB_ORG:?Set --org or GITHUB_ORG in $CONFIG_FILE}"

clear
header "Admin Access Report — $GITHUB_ORG"
echo -e "  Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo ""

# ── 1. Current org owners ─────────────────────────────────────────────────────
step "Current Organisation Owners (Admin)"
echo ""

OWNERS=$(gh api "/orgs/$GITHUB_ORG/members?role=admin&per_page=100" \
  --jq '.[] | "  \(.login)\t\(.html_url)"' 2>/dev/null || echo "")

if [[ -z "$OWNERS" ]]; then
  warn "  Could not fetch org owners. Ensure your token has read:org scope."
else
  COUNT=$(echo "$OWNERS" | wc -l | tr -d ' ')
  echo -e "  ${BOLD}$COUNT org owner(s):${NC}"
  echo ""
  while IFS=$'\t' read -r login url; do
    echo -e "  ${GREEN}•${NC}  $login  ${DIM}$url${NC}"
  done <<< "$OWNERS"
fi

# ── 2. Repo admins ─────────────────────────────────────────────────────────────
echo ""
step "Repositories with Direct Admin Collaborators (non-team)"
echo ""
info "Fetching repos (this may take a moment for large orgs)..."

REPOS=$(gh api "/orgs/$GITHUB_ORG/repos?per_page=100&type=all" \
  --jq '.[].name' 2>/dev/null || echo "")

FOUND_ANY=false
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  ADMINS=$(gh api "/repos/$GITHUB_ORG/$repo/collaborators?affiliation=direct&permission=admin&per_page=50" \
    --jq '.[].login' 2>/dev/null || echo "")
  if [[ -n "$ADMINS" ]]; then
    FOUND_ANY=true
    echo -e "  ${YELLOW}$GITHUB_ORG/$repo${NC}:"
    while IFS= read -r admin; do
      echo -e "    ${RED}!${NC}  $admin (direct admin — should be via team)"
    done <<< "$ADMINS"
  fi
done <<< "$REPOS"

$FOUND_ANY || success "  No direct admin collaborators found (all access is team-based ✓)"

# ── 3. Teams with admin on repos ──────────────────────────────────────────────
echo ""
step "Teams with Admin Permission on Repositories"
echo ""

TEAMS=$(gh api "/orgs/$GITHUB_ORG/teams?per_page=100" \
  --jq '.[].slug' 2>/dev/null || echo "")

while IFS= read -r team; do
  [[ -z "$team" ]] && continue
  ADMIN_REPOS=$(gh api "/orgs/$GITHUB_ORG/teams/$team/repos?per_page=100" \
    --jq '.[] | select(.permissions.admin == true) | .name' 2>/dev/null || echo "")
  if [[ -n "$ADMIN_REPOS" ]]; then
    echo -e "  ${CYAN}$team${NC} has admin on:"
    while IFS= read -r r; do
      echo -e "    • $r"
    done <<< "$ADMIN_REPOS"
  fi
done <<< "$TEAMS"

# ── 4. Recent audit log events (if enterprise access available) ────────────────
echo ""
step "Recent Admin Changes (Audit Log — last 30 days)"

if [[ -n "${GITHUB_ENTERPRISE:-}" ]]; then
  echo ""
  info "Querying enterprise audit log for $GITHUB_ENTERPRISE..."

  ACTIONS=(
    "org.add_member"
    "org.remove_member"
    "repo.add_member"
    "repo.remove_member"
    "team.add_member"
    "team.remove_member"
  )

  for action in "${ACTIONS[@]}"; do
    EVENTS=$(gh api \
      "/enterprises/$GITHUB_ENTERPRISE/audit-log?phrase=action:$action&per_page=20" \
      --jq '.[] | "  \(.created_at[:10])  \(.actor)\t→ \(.action)\t\(.repo // .team // "")"' \
      2>/dev/null || echo "")
    if [[ -n "$EVENTS" ]]; then
      echo -e "\n  ${BOLD}$action:${NC}"
      while IFS=$'\t' read -r date_actor action_col repo; do
        echo -e "  $date_actor  ${DIM}$repo${NC}"
      done <<< "$EVENTS"
    fi
  done
else
  warn "GITHUB_ENTERPRISE not set — skipping audit log query."
  info "Set it in $CONFIG_FILE or pass --enterprise your-enterprise-slug"
  echo ""
  info "Manual query:"
  echo '  gh api "/enterprises/{enterprise}/audit-log?phrase=action:org.add_member&per_page=50"'
fi

# ── 5. Platform admins team membership ────────────────────────────────────────
echo ""
step "platform-admins Team Members"
echo ""

PLATFORM_ADMINS=$(gh api "/orgs/${PLATFORM_ORG:-$GITHUB_ORG}/teams/platform-admins/members?per_page=100" \
  --jq '.[].login' 2>/dev/null || echo "")

if [[ -z "$PLATFORM_ADMINS" ]]; then
  warn "  Could not fetch platform-admins team (team may not exist yet)"
else
  while IFS= read -r user; do
    ROLE=$(gh api "/orgs/${PLATFORM_ORG:-$GITHUB_ORG}/teams/platform-admins/memberships/$user" \
      --jq '.role' 2>/dev/null || echo "member")
    ROLE_COLOUR=$([[ "$ROLE" == "maintainer" ]] && echo "$YELLOW" || echo "$GREEN")
    echo -e "  ${ROLE_COLOUR}•${NC}  $user  ${DIM}($ROLE)${NC}"
  done <<< "$PLATFORM_ADMINS"
fi

echo ""
divider
echo ""
info "For compliance evidence export: gh api '/enterprises/{enterprise}/audit-log' --paginate > audit-export.json"
info "Full report: $GOV_URL/issues?labels=audit-report"
