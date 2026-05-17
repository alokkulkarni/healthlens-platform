#!/usr/bin/env bash
# setup/09-base-teams.sh — Create the four base governance teams

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${PLATFORM_ORG:?Set --platform-org}"

step "Creating base governance teams in $PLATFORM_ORG"
info "You will be prompted to add the initial members for each team."
echo ""

# Format: "slug|name|description|privacy"
TEAMS=(
  "platform-admins|Platform Admins|Own and maintain all governance controls. Admin on all repos.|secret"
  "compliance-team|Compliance Team|Approve/reject waivers and view compliance reports.|closed"
  "internal-audit|Internal Audit|Read-only access to all compliance evidence and audit reports.|closed"
  "all-engineers|All Engineers|All engineering staff. Can open waiver requests.|closed"
)

for entry in "${TEAMS[@]}"; do
  IFS='|' read -r slug name description privacy <<< "$entry"

  echo ""
  divider
  echo -e "${BOLD}  Team: $name${NC} ($slug)"
  echo -e "  ${DIM}$description${NC}"
  echo ""

  if team_exists "$PLATFORM_ORG" "$slug"; then
    info "  Team already exists: $slug"
    confirm "  Update members for $name?" || continue
  else
    info "  Creating team: $slug"
    if ! gh api --method POST "/orgs/$PLATFORM_ORG/teams" \
         --field name="$name" \
         --field slug="$slug" \
         --field description="$description" \
         --field privacy="$privacy" &>/dev/null; then
      warn "  Could not create $slug — may need org owner rights or team already exists"
    else
      success "  Created: $slug"
    fi
  fi

  # Ask for initial members
  echo ""
  echo -e "  ${CYAN}Enter GitHub usernames to add to this team.${NC}"
  echo -e "  ${DIM}Press Enter without a name when done.${NC}"

  MAINTAINER_ADDED=false
  while true; do
    read -rp "$(echo -e "    ${CYAN}Username (or Enter to skip): ${NC}")" username
    [[ -z "$username" ]] && break

    # First member of platform-admins gets maintainer role
    local_role="member"
    if [[ "$slug" == "platform-admins" && "$MAINTAINER_ADDED" == "false" ]]; then
      local_role="maintainer"
      MAINTAINER_ADDED=true
      info "  First platform-admin set as maintainer: $username"
    fi

    if gh api --method PUT "/orgs/$PLATFORM_ORG/teams/$slug/memberships/$username" \
         --field role="$local_role" &>/dev/null; then
      success "  Added $username as $local_role"
    else
      warn "  Could not add $username — check the username is correct and the account exists in the org"
    fi
  done
done

step "Setting governance repo permissions for all teams"
declare -A PERMS=(
  ["platform-admins"]="admin"
  ["compliance-team"]="push"
  ["internal-audit"]="pull"
  ["all-engineers"]="pull"
)

for slug in "${!PERMS[@]}"; do
  perm="${PERMS[$slug]}"
  if gh api --method PUT \
       "/orgs/$PLATFORM_ORG/teams/$slug/repos/$PLATFORM_ORG/$GOVERNANCE_REPO" \
       --field permission="$perm" &>/dev/null; then
    success "  $slug → $perm on $GOVERNANCE_REPO"
  else
    warn "  Could not set $slug → $perm"
  fi
done

echo ""
success "Base teams configured"
info "Manage team memberships at: https://github.com/orgs/$PLATFORM_ORG/teams"
