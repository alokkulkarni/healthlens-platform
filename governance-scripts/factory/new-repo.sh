#!/usr/bin/env bash
# factory/new-repo.sh — Interactive: request a new repository via the governance repo
# Prompts for all required fields, validates them, generates YAML, and creates a PR.
# Usage: bash factory/new-repo.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config
check_prereqs

: "${PLATFORM_ORG:?Run setup-all.sh first or set PLATFORM_ORG in $CONFIG_FILE}"
: "${GOVERNANCE_REPO:?Run setup-all.sh first or set GOVERNANCE_REPO in $CONFIG_FILE}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

clear
header "New Repository Request"
info "This will guide you through creating a new repository."
info "Your answers will be validated, turned into a YAML definition, and"
info "submitted as a PR to ${BOLD}$PLATFORM_ORG/$GOVERNANCE_REPO${NC}."
info "A platform admin must approve the PR before the repo is created."
echo ""

# ── Repository basics ──────────────────────────────────────────────────────────
step "1. Repository Basics"

required_input "Repository name (lowercase, hyphens only — e.g. payment-service)" REPO_NAME
# Validate: only lowercase, digits, hyphens
if [[ ! "$REPO_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
  error "Invalid repo name. Use only lowercase letters, digits, and hyphens (no leading/trailing hyphens)."
  exit 1
fi
# Check repo doesn't already exist
if gh api "/repos/$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
  error "Repository '$GITHUB_ORG/$REPO_NAME' already exists."
  exit 1
fi

required_input "One-line description of what this repo does" REPO_DESCRIPTION

echo ""
echo -e "  Visibility options:"
echo -e "    ${DIM}1${NC}. private  (default — recommended for most services)"
echo -e "    ${DIM}2${NC}. internal (visible to all org members — for shared tooling)"
echo -e "    ${DIM}3${NC}. public   (requires written justification)"
read -rp "$(echo -e "  ${CYAN}Select visibility [1]: ${NC}")" VIS_CHOICE
case "${VIS_CHOICE:-1}" in
  1|"") VISIBILITY="private" ;;
  2)    VISIBILITY="internal" ;;
  3)    VISIBILITY="public"
        required_input "Public repo justification (mandatory)" PUBLIC_JUSTIFICATION ;;
  *)    VISIBILITY="private" ;;
esac
info "  Visibility: $VISIBILITY"

# ── Classification ─────────────────────────────────────────────────────────────
echo ""
step "2. Risk Classification"
echo ""
echo -e "  Risk tier definitions:"
echo -e "    ${DIM}1${NC}. ${GREEN}standard${NC}  — internal tooling, non-production services"
echo -e "    ${DIM}2${NC}. ${YELLOW}elevated${NC}  — customer-facing services, handles user data"
echo -e "    ${DIM}3${NC}. ${RED}critical${NC}  — production financial/PII systems (requires CISO awareness)"
read -rp "$(echo -e "  ${CYAN}Select risk tier [1]: ${NC}")" RISK_CHOICE
case "${RISK_CHOICE:-1}" in
  1|"") RISK_TIER="standard" ;;
  2)    RISK_TIER="elevated" ;;
  3)    RISK_TIER="critical"
        warn "  Critical tier — this will be flagged in audit reports." ;;
  *)    RISK_TIER="standard" ;;
esac
info "  Risk tier: $RISK_TIER"

required_input "Business domain (e.g. payments, identity, platform, reporting)" BUSINESS_DOMAIN

optional_input "Topics (comma-separated tags, e.g. java,microservice,payments)" TOPICS_INPUT ""
# Convert comma-separated to YAML list
TOPICS_YAML=""
if [[ -n "$TOPICS_INPUT" ]]; then
  IFS=',' read -ra TOPIC_ARR <<< "$TOPICS_INPUT"
  TOPICS_YAML="topics:"
  for t in "${TOPIC_ARR[@]}"; do
    t_clean=$(echo "$t" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    TOPICS_YAML+=$'\n'"  - $t_clean"
  done
fi

# ── Starter template ───────────────────────────────────────────────────────────
echo ""
step "3. Starter Template (optional)"
info "If your language/framework has a pre-approved template repo in $PLATFORM_ORG, enter its name."
info "Leave blank to start with an empty repository."
optional_input "Template repo name (blank = empty repo)" TEMPLATE_NAME ""

# ── Team access ────────────────────────────────────────────────────────────────
echo ""
step "4. Team Access"
echo ""
info "Every repo needs at least one team with push access."
info "platform-admins will be added as admin automatically."
echo ""

TEAM_ACCESS_YAML="team_access:
  - team: platform-admins
    permission: admin"

TEAM_COUNT=0
while true; do
  TEAM_COUNT=$((TEAM_COUNT + 1))
  echo -e "  ${CYAN}Team #$TEAM_COUNT${NC} (press Enter with blank team name to finish):"
  read -rp "$(echo -e "    Team slug: ")" TEAM_SLUG
  [[ -z "$TEAM_SLUG" ]] && break

  # Validate team exists
  if ! team_exists "$PLATFORM_ORG" "$TEAM_SLUG" && ! team_exists "$GITHUB_ORG" "$TEAM_SLUG"; then
    warn "  Team '$TEAM_SLUG' not found in org. It must be created first via factory/new-team.sh"
    confirm "  Add it anyway (it may be created later)?" || continue
  fi

  echo -e "    Permission options: ${DIM}read${NC} | ${DIM}triage${NC} | ${DIM}push${NC} | ${DIM}maintain${NC} | ${DIM}admin${NC}"
  read -rp "$(echo -e "    Permission [push]: ")" TEAM_PERM
  TEAM_PERM="${TEAM_PERM:-push}"

  TEAM_ACCESS_YAML+=$'\n'"  - team: $TEAM_SLUG"$'\n'"    permission: $TEAM_PERM"
  success "  Added: $TEAM_SLUG → $TEAM_PERM"
done

if [[ $TEAM_COUNT -eq 1 ]]; then
  error "At least one team (besides platform-admins) must be added. Please re-run."
  exit 1
fi

# ── CODEOWNERS ─────────────────────────────────────────────────────────────────
echo ""
step "5. CODEOWNERS — Who Must Review Code Changes"
echo ""
info "CODEOWNERS controls who is automatically added as a required reviewer."
info "Use team references: @${GITHUB_ORG}/team-slug or @username"
echo ""

CODEOWNERS_YAML="codeowners:
  - pattern: \".github/**\"
    owners:
      - \"@${PLATFORM_ORG}/platform-admins\""

info "Default owner for ALL files (required):"
required_input "Default CODEOWNER (e.g. @${GITHUB_ORG}/my-team or @username)" DEFAULT_OWNER

CODEOWNERS_YAML+=$'\n'"  - pattern: \"**\""$'\n'"    owners:"$'\n'"      - \"$DEFAULT_OWNER\""

echo ""
info "Add more specific CODEOWNERS rules (optional — e.g. for src/api/** or docs/**)."
echo -e "  ${DIM}Press Enter with blank pattern to finish.${NC}"

while true; do
  echo ""
  read -rp "$(echo -e "  ${CYAN}File pattern (blank to finish): ${NC}")" CO_PATTERN
  [[ -z "$CO_PATTERN" ]] && break
  required_input "Owner(s) for $CO_PATTERN (space-separated, e.g. @org/team @username)" CO_OWNERS
  # Build YAML owners list
  CO_OWNERS_YAML="    owners:"
  IFS=' ' read -ra OWNER_ARR <<< "$CO_OWNERS"
  for o in "${OWNER_ARR[@]}"; do
    CO_OWNERS_YAML+=$'\n'"      - \"$o\""
  done
  CODEOWNERS_YAML+=$'\n'"  - pattern: \"$CO_PATTERN\""$'\n'"$CO_OWNERS_YAML"
  success "  Added CODEOWNER rule: $CO_PATTERN → $CO_OWNERS"
done

# ── Request metadata ───────────────────────────────────────────────────────────
echo ""
step "6. Request Metadata"

CURRENT_USER=$(gh api /user --jq '.login' 2>/dev/null || echo "")
optional_input "Your GitHub username" REQUESTED_BY "${CURRENT_USER}"
required_input "Business justification (why does this repo need to exist?)" BIZ_JUSTIFICATION

# ── Generate YAML ──────────────────────────────────────────────────────────────
echo ""
step "Generating YAML definition"

YAML_FILE="repos/${REPO_NAME}.yml"
YAML_CONTENT="# Repository definition — auto-generated by new-repo.sh
# Requested by: $REQUESTED_BY on $(date -u +%Y-%m-%d)

name: \"$REPO_NAME\"
description: \"$REPO_DESCRIPTION\"
visibility: $VISIBILITY
risk_tier: $RISK_TIER
business_domain: \"$BUSINESS_DOMAIN\"
${TOPICS_YAML:-topics: []}
template: \"${TEMPLATE_NAME:-}\"

$TEAM_ACCESS_YAML

$CODEOWNERS_YAML

default_branch: main
requested_by: \"$REQUESTED_BY\"
business_justification: \"$BIZ_JUSTIFICATION\"${VISIBILITY:+}"

# Add public justification if needed
if [[ "$VISIBILITY" == "public" ]]; then
  YAML_CONTENT+=$'\n'"public_visibility_justification: \"${PUBLIC_JUSTIFICATION:-}\""
fi

echo ""
echo -e "${DIM}──────────── Generated YAML ────────────${NC}"
echo "$YAML_CONTENT"
echo -e "${DIM}────────────────────────────────────────${NC}"
echo ""

confirm "Does this look correct? Submit this as a PR to $PLATFORM_ORG/$GOVERNANCE_REPO?" || {
  info "Cancelled. No changes made."
  exit 0
}

# ── Create PR ─────────────────────────────────────────────────────────────────
step "Creating Pull Request"

# Clone governance repo, create branch, push YAML, open PR
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

info "Cloning governance repository..."
gh repo clone "$PLATFORM_ORG/$GOVERNANCE_REPO" "$TEMP_DIR/governance" -- --depth 1 --quiet

cd "$TEMP_DIR/governance"

BRANCH_NAME="repo-request/${REPO_NAME}-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH_NAME" &>/dev/null

mkdir -p repos
echo "$YAML_CONTENT" > "repos/${REPO_NAME}.yml"

git config user.email "${REQUESTED_BY}@github.com"
git config user.name "$REQUESTED_BY"
git add "repos/${REPO_NAME}.yml"
git commit -m "feat: request new repository ${REPO_NAME}

Risk tier: $RISK_TIER
Domain: $BUSINESS_DOMAIN
Requested by: $REQUESTED_BY
Justification: $BIZ_JUSTIFICATION" --quiet

git push origin "$BRANCH_NAME" --quiet

PR_URL=$(gh pr create \
  --title "New repo request: $REPO_NAME" \
  --body "## New Repository Request

**Repository:** \`$GITHUB_ORG/$REPO_NAME\`
**Description:** $REPO_DESCRIPTION
**Visibility:** $VISIBILITY
**Risk tier:** $RISK_TIER
**Domain:** $BUSINESS_DOMAIN
**Requested by:** @$REQUESTED_BY

### Justification
$BIZ_JUSTIFICATION

### What will be auto-provisioned on merge
- Repository created in \`$GITHUB_ORG\` with all settings from the YAML
- Teams assigned with correct permissions
- \`CODEOWNERS\` file created
- \`compliance.yml\` workflow added
- PR template added
- Risk tier label added

> Platform admin: review the YAML, approve if correct, and merge to trigger provisioning." \
  --repo "$PLATFORM_ORG/$GOVERNANCE_REPO" \
  --base main \
  --head "$BRANCH_NAME")

cd - &>/dev/null

echo ""
success "Pull Request created: $PR_URL"
echo ""
info "Next steps:"
echo "  1. A platform admin will review your PR"
echo "  2. On approval and merge, the repo will be automatically created"
echo "  3. You will be tagged in the provisioning summary issue"
echo ""
info "While you wait, create any needed teams: bash factory/new-team.sh"
