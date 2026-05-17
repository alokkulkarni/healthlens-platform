#!/usr/bin/env bash
# setup/10-finalize.sh — Print secrets checklist, verify setup, show next steps

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    --enterprise)      GITHUB_ENTERPRISE="$2"; shift 2 ;;
    --admin-email)     ADMIN_EMAIL="$2";     shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

GOV_URL="https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO"
SETTINGS_URL="$GOV_URL/settings/secrets/actions"

header "Setup Complete — Final Checklist"

echo ""
echo -e "${BOLD}The following GitHub Actions secrets must be set manually${NC}"
echo -e "${DIM}Go to: $SETTINGS_URL${NC}"
echo ""

# Secrets table
printf "%-40s %-15s %s\n" "SECRET NAME" "SCOPE" "PURPOSE"
divider
printf "%-40s %-15s %s\n" "GOVERNANCE_READ_TOKEN"    "org (all repos)" "PAT with issues:read on governance repo — used by waiver-check in app repos"
printf "%-40s %-15s %s\n" "REPO_FACTORY_TOKEN"       "governance repo" "PAT/App token with repo+admin:org — used by repo and team factory"
printf "%-40s %-15s %s\n" "AUDIT_REPORT_TOKEN"       "governance repo" "PAT with read:org + read:audit_log — used by central audit report"
printf "%-40s %-15s %s\n" "SONAR_TOKEN"              "org (all repos)" "SonarQube auth token for compliance workflow"
printf "%-40s %-15s %s\n" "SONAR_HOST_URL"           "org (all repos)" "SonarQube server URL (e.g. https://sonar.mycompany.com)"
printf "%-40s %-15s %s\n" "NEXUS_IQ_URL"             "org (all repos)" "Nexus IQ server URL"
printf "%-40s %-15s %s\n" "NEXUS_IQ_USERNAME"        "org (all repos)" "Nexus IQ service account username"
printf "%-40s %-15s %s\n" "NEXUS_IQ_PASSWORD"        "org (all repos)" "Nexus IQ service account password"
printf "%-40s %-15s %s\n" "STAGING_APP_URL"          "org (all repos)" "DAST target URL — staging environment for ZAP scans"

echo ""

# Variables
echo -e "${BOLD}Repository Variables${NC} (Settings → Variables):"
echo ""
printf "%-40s %s\n" "VARIABLE NAME" "VALUE"
divider
printf "%-40s %s\n" "GITHUB_ORG_NAME" "$GITHUB_ORG (the engineering org repo factory creates repos in)"

echo ""
divider

step "Verifying governance repository contents"
echo ""

FILES_TO_CHECK=(
  ".github/CODEOWNERS"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/waiver-request.yml"
  ".github/workflows/waiver-process.yml"
  ".github/workflows/waiver-check.yml"
  ".github/workflows/waiver-expiry.yml"
  ".github/workflows/waiver-report.yml"
  ".github/workflows/central-audit-report.yml"
  ".github/workflows/repo-factory.yml"
  ".github/workflows/team-factory.yml"
  ".github/templates/compliance.yml"
  "repos/_template.yml"
  "teams/_template.yml"
  "README.md"
)

ALL_PRESENT=true
for file in "${FILES_TO_CHECK[@]}"; do
  if gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/contents/$file" &>/dev/null; then
    success "  $file"
  else
    error "  MISSING: $file"
    ALL_PRESENT=false
  fi
done

echo ""
if $ALL_PRESENT; then
  success "All governance files are present"
else
  warn "Some files are missing — re-run the relevant setup steps"
fi

step "Verifying labels"
LABEL_COUNT=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/labels?per_page=50" \
  --jq 'length' 2>/dev/null || echo "0")
if [[ "$LABEL_COUNT" -ge 9 ]]; then
  success "Labels: $LABEL_COUNT created"
else
  warn "Only $LABEL_COUNT labels found — re-run step 8 (08-labels.sh)"
fi

step "Verifying teams"
for slug in platform-admins compliance-team internal-audit all-engineers; do
  if team_exists "$PLATFORM_ORG" "$slug"; then
    success "  Team: $slug"
  else
    warn "  Missing team: $slug — re-run step 9 (09-base-teams.sh)"
  fi
done

header "Next Steps"

cat << NEXTSTEPS
  1. Set all secrets listed above in the governance repository
     → $SETTINGS_URL

  2. Set GOVERNANCE_READ_TOKEN as an org-level secret so all engineering repos can use it
     → https://github.com/organizations/$GITHUB_ORG/settings/secrets/actions

  3. Add the current user/bot to platform-admins team
     → https://github.com/orgs/$PLATFORM_ORG/teams/platform-admins

  4. Test the repo factory end-to-end:
     $ bash governance-scripts/factory/new-repo.sh

  5. Test the team factory:
     $ bash governance-scripts/factory/new-team.sh

  6. Manually trigger the compliance report to verify it works:
     $ gh workflow run waiver-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  7. Manually trigger the audit report:
     $ gh workflow run central-audit-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  8. Verify a real PR in an app repo has all compliance checks running
     (After adding compliance.yml to the repo via factory or manually)

  9. Brief your team:
     - Engineers: how to request a repo (repos/_template.yml PR)
     - Engineers: how to raise a waiver (Issues → Waiver Request)
     - Risk owners: how to approve (/approve-waiver comment)
     - Compliance team: where to find weekly reports (Issues → compliance-report label)
     - Internal Audit: access to $GOV_URL

NEXTSTEPS

echo -e "${BOLD}${GREEN}Setup complete. Governance framework is live at:${NC}"
echo -e "  ${BOLD}$GOV_URL${NC}"
echo ""
