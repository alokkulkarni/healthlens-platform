#!/usr/bin/env bash
# setup/02-governance-repo.sh — Create the central governance repository
# Creates repo, sets team access, creates directory skeleton

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)            GITHUB_ORG="$2";        shift 2 ;;
    --platform-org)   PLATFORM_ORG="$2";      shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2";  shift 2 ;;
    --enterprise)     GITHUB_ENTERPRISE="$2"; shift 2 ;;
    --admin-email)    ADMIN_EMAIL="$2";        shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"

step "Creating governance repository: $PLATFORM_ORG/$GOVERNANCE_REPO"

if repo_exists "$PLATFORM_ORG" "$GOVERNANCE_REPO"; then
  warn "Repository already exists: $PLATFORM_ORG/$GOVERNANCE_REPO — skipping creation"
else
  gh api --method POST "/orgs/$PLATFORM_ORG/repos" \
    --field name="$GOVERNANCE_REPO" \
    --field description="Central governance — compliance controls, waiver registry, repo factory, and audit reports" \
    --field visibility=private \
    --field has_issues=true \
    --field has_projects=false \
    --field has_wiki=false \
    --field delete_branch_on_merge=true \
    --field auto_init=true \
    --jq '.html_url' | xargs -I{} info "Created: {}"
  
  # Wait for GitHub to initialise the repo
  sleep 3
  success "Governance repository created"
fi

step "Setting up required teams"
# Create teams if they don't exist
declare -A TEAMS=(
  ["platform-admins"]="Platform admins — own and maintain governance controls"
  ["compliance-team"]="Compliance team — approve/reject waivers, view reports"
  ["internal-audit"]="Internal Audit — read-only access to all compliance evidence"
  ["all-engineers"]="All engineers — can open waiver requests"
)

for slug in "${!TEAMS[@]}"; do
  if team_exists "$PLATFORM_ORG" "$slug"; then
    info "  Team already exists: $slug"
  else
    gh api --method POST "/orgs/$PLATFORM_ORG/teams" \
      --field name="${slug//-/ }" \
      --field slug="$slug" \
      --field description="${TEAMS[$slug]}" \
      --field privacy=closed &>/dev/null && success "  Created team: $slug" || warn "  Could not create team: $slug"
  fi
done

step "Setting team permissions on governance repository"
declare -A TEAM_PERMS=(
  ["platform-admins"]="admin"
  ["compliance-team"]="push"
  ["internal-audit"]="pull"
  ["all-engineers"]="pull"
)

for slug in "${!TEAM_PERMS[@]}"; do
  perm="${TEAM_PERMS[$slug]}"
  if gh api --method PUT "/orgs/$PLATFORM_ORG/teams/$slug/repos/$PLATFORM_ORG/$GOVERNANCE_REPO" \
       --field permission="$perm" &>/dev/null; then
    success "  $slug → $perm"
  else
    warn "  Could not set $slug → $perm (team may not exist yet)"
  fi
done

step "Creating governance repository directory structure"
info "Creating placeholder files to establish folder structure..."

# README for repos directory
push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" "repos/README.md" \
  "# Repository Definitions

Add one YAML file per repository here.
Copy \`_template.yml\`, rename it to \`{repo-name}.yml\`, fill in the fields, and open a PR.

A platform admin will review. On merge, the repository is automatically provisioned." \
  "chore: add repos directory [governance-setup]"

# README for teams directory
push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" "teams/README.md" \
  "# Team Definitions

Add one YAML file per team here.
Copy \`_template.yml\`, rename it to \`{team-slug}.yml\`, fill in the fields, and open a PR.

On merge, the team is automatically created or updated." \
  "chore: add teams directory [governance-setup]"

# README for templates
push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" ".github/templates/README.md" \
  "# Canonical Workflow Templates

These files are copied into every new repository by the repo factory.
Update \`compliance.yml\` here when the compliance workflow changes.
Run \`factory/sync-compliance.sh\` to push the updated version to all existing repos." \
  "chore: add templates directory [governance-setup]"

# README for org-settings
push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" "org-settings/README.md" \
  "# Organisation Settings

Documents organisation-level policies that are applied by the setup scripts.
See the governance guide Part 1 for how these are applied." \
  "chore: add org-settings directory [governance-setup]"

# Main README
push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" "README.md" \
  "# GitHub Governance Repository

This is the central governance repository. **All** compliance controls, waiver requests, and audit reports live here.

## How to request a new repository
1. Copy \`repos/_template.yml\` → \`repos/your-repo-name.yml\`
2. Fill in all fields (see template comments)
3. Open a PR — platform admins are automatically added as required reviewers
4. On approval and merge, the repository is provisioned automatically

## How to request a new team
1. Copy \`teams/_template.yml\` → \`teams/your-team-slug.yml\`
2. Fill in team name, description, members
3. Open a PR → platform admin approval → auto-provisioned

## How to raise a compliance waiver
1. Go to Issues → New Issue → Compliance Waiver Request
2. Fill in the form (select the exact failing check from the dropdown)
3. The risk owner listed will be notified to approve

## Compliance reports
Generated every Monday as Issues with the \`compliance-report\` label.
Central audit reports use the \`audit-report\` label.

## Contacts
- Platform Governance team: @platform-org/platform-admins
" \
  "chore: add governance README [governance-setup]"

success "Governance repository structure created"
info "View at: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO"
