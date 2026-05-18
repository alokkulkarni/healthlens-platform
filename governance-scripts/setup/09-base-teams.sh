#!/usr/bin/env bash
# setup/09-base-teams.sh — Create the four base governance teams

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${PLATFORM_ORG:?Set --platform-org}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

TWO_ORG_MODE=false
[[ "$PLATFORM_ORG" != "$GITHUB_ORG" ]] && TWO_ORG_MODE=true

create_team_with_members() {
  local org="$1" slug="$2" name="$3" description="$4" privacy="$5" first_is_maintainer="$6"

  echo ""
  divider
  echo -e "${BOLD}  Team: $name${NC} ($slug) in ${CYAN}$org${NC}"
  echo -e "  ${DIM}$description${NC}"
  echo ""

  if team_exists "$org" "$slug"; then
    info "  Team already exists: $slug"
    confirm "  Update members for $name?" || return 0
  else
    info "  Creating team: $slug"
    if ! gh api --method POST "/orgs/$org/teams" \
         --field name="$name" \
         --field slug="$slug" \
         --field description="$description" \
         --field privacy="$privacy" &>/dev/null; then
      warn "  Could not create $slug — may need org owner rights"
      return
    fi
    success "  Created: $slug"
  fi

  echo ""
  echo -e "  ${CYAN}Enter GitHub usernames to add to this team.${NC}"
  echo -e "  ${DIM}Press Enter without a name when done.${NC}"

  local maintainer_added=false
  while true; do
    read -rp "$(echo -e "    ${CYAN}Username (or Enter to skip): ${NC}")" username
    [[ -z "$username" ]] && break

    local role="member"
    if [[ "$first_is_maintainer" == "true" && "$maintainer_added" == "false" ]]; then
      role="maintainer"
      maintainer_added=true
      info "  First member set as maintainer: $username"
    fi

    if gh api --method PUT "/orgs/$org/teams/$slug/memberships/$username" \
         --field role="$role" &>/dev/null; then
      success "  Added $username as $role"
    else
      warn "  Could not add $username — check username exists in org"
    fi
  done
}

# ── Governance org teams (in PLATFORM_ORG) ────────────────────────────────────
step "Creating governance teams in $PLATFORM_ORG (restricted governance org)"
if $TWO_ORG_MODE; then
  info "Two-org mode: governance teams → $PLATFORM_ORG | engineering teams → $GITHUB_ORG"
  info "Engineering org owners/members will NOT have access to $PLATFORM_ORG"
fi
echo ""

create_team_with_members "$PLATFORM_ORG" "platform-admins" "Platform Admins" \
  "Own and maintain all governance controls — admin on governance repo" "secret" "true"

create_team_with_members "$PLATFORM_ORG" "compliance-team" "Compliance Team" \
  "Approve/reject waivers and view compliance reports" "closed" "false"

create_team_with_members "$PLATFORM_ORG" "internal-audit" "Internal Audit" \
  "Read-only access to all compliance evidence and audit reports" "closed" "false"

# ── Engineering org teams (in GITHUB_ORG) ────────────────────────────────────
if $TWO_ORG_MODE; then
  echo ""
  step "Creating engineering teams in $GITHUB_ORG"
  info "These teams exist only in the engineering org — they have no access to $PLATFORM_ORG"
  echo ""

  create_team_with_members "$GITHUB_ORG" "all-engineers" "All Engineers" \
    "All engineering staff — can open waiver requests" "closed" "false"

  create_team_with_members "$GITHUB_ORG" "security-reviewers" "Security Reviewers" \
    "Security champions — review GHAS alerts and waiver risk decisions" "closed" "false"

  # bypass-approved team: empty by default.
  # Members are added temporarily by the access-request approval workflow
  # and give the user bypass-actor status on the baseline-security-controls ruleset.
  # DO NOT add permanent members — this team should always be empty at rest.
  step "Creating bypass-approved team in $GITHUB_ORG (empty by default)"
  if ! team_exists "$GITHUB_ORG" "bypass-approved"; then
    if gh api --method POST "/orgs/$GITHUB_ORG/teams" \
         --field name="bypass-approved" \
         --field description="Temporary bypass-actor team — members set by access-request workflow only. Must be empty at rest." \
         --field privacy="secret" &>/dev/null; then
      success "  bypass-approved team created (empty)"
    else
      warn "  Could not create bypass-approved team"
    fi
  else
    info "  bypass-approved team already exists"
  fi

  # Wire bypass-approved team into baseline-security-controls ruleset as bypass actor
  step "Adding bypass-approved team as bypass actor on baseline-security-controls"
  BYPASS_TEAM_ID=$(gh api "/orgs/$GITHUB_ORG/teams/bypass-approved" --jq '.id' 2>/dev/null || echo "")
  RULESET_ID=$(gh api "/orgs/$GITHUB_ORG/rulesets" \
    --jq '.[] | select(.name == "baseline-security-controls") | .id' 2>/dev/null || echo "")

  if [[ -n "$BYPASS_TEAM_ID" && -n "$RULESET_ID" ]]; then
    # Fetch existing ruleset and append the bypass team to bypass_actors
    CURRENT=$(gh api "/orgs/$GITHUB_ORG/rulesets/$RULESET_ID" 2>/dev/null || echo "")
    if [[ -n "$CURRENT" ]]; then
      UPDATED=$(echo "$CURRENT" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
actors = rs.get('bypass_actors', [])
team_id = int('$BYPASS_TEAM_ID')
# Add if not already present
if not any(a.get('actor_id') == team_id and a.get('actor_type') == 'Team' for a in actors):
    actors.append({'actor_id': team_id, 'actor_type': 'Team', 'bypass_mode': 'always'})
rs['bypass_actors'] = actors
print(json.dumps(rs))
" 2>/dev/null || echo "")
      if [[ -n "$UPDATED" ]]; then
        if gh api --method PUT "/orgs/$GITHUB_ORG/rulesets/$RULESET_ID" \
             --input - <<< "$UPDATED" &>/dev/null; then
          success "  bypass-approved team (ID: $BYPASS_TEAM_ID) added as bypass actor on baseline-security-controls"
        else
          warn "  Could not update ruleset bypass actors — add manually:"
          warn "  Org Settings → Rules → Rulesets → baseline-security-controls → Bypass list → Add team: bypass-approved"
        fi
      fi
    fi
  else
    [[ -z "$BYPASS_TEAM_ID" ]] && warn "  Could not get bypass-approved team ID — run step 9 again after team is created"
    [[ -z "$RULESET_ID" ]]     && warn "  baseline-security-controls ruleset not found — run step 7 first"
  fi
else
  # Single-org mode — all teams in the same org
  create_team_with_members "$PLATFORM_ORG" "all-engineers" "All Engineers" \
    "All engineering staff — can open waiver requests" "closed" "false"
fi

# ── Governance repo permissions (only governance org teams) ───────────────────
echo ""
step "Setting governance repo permissions ($PLATFORM_ORG/$GOVERNANCE_REPO)"
info "Only governance org teams are granted access — engineering teams have NO access"
echo ""

declare -A GOV_PERMS=(
  ["platform-admins"]="admin"
  ["compliance-team"]="push"
  ["internal-audit"]="pull"
)

for slug in "${!GOV_PERMS[@]}"; do
  perm="${GOV_PERMS[$slug]}"
  if gh api --method PUT \
       "/orgs/$PLATFORM_ORG/teams/$slug/repos/$PLATFORM_ORG/$GOVERNANCE_REPO" \
       --field permission="$perm" &>/dev/null; then
    success "  $slug → $perm on $GOVERNANCE_REPO"
  else
    warn "  Could not set $slug → $perm"
  fi
done

echo ""
if $TWO_ORG_MODE; then
  echo -e "  ${BOLD}Isolation verified:${NC}"
  echo -e "  ${GREEN}✓${NC}  Governance teams live in: $PLATFORM_ORG"
  echo -e "  ${GREEN}✓${NC}  Engineering teams live in: $GITHUB_ORG"
  echo -e "  ${GREEN}✓${NC}  Engineering teams have zero access to governance repo"
  echo -e "  ${YELLOW}!${NC}  Cross-org link is read-only via GOVERNANCE_READ_TOKEN secret only"
fi
echo ""
success "Base teams configured"
info "Governance teams: https://github.com/orgs/$PLATFORM_ORG/teams"
$TWO_ORG_MODE && info "Engineering teams: https://github.com/orgs/$GITHUB_ORG/teams"
