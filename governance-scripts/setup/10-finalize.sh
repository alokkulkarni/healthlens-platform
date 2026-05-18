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

TWO_ORG_MODE=false
[[ "$PLATFORM_ORG" != "$GITHUB_ORG" ]] && TWO_ORG_MODE=true

GOV_URL="https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO"
GOV_SECRETS_URL="$GOV_URL/settings/secrets/actions"
ENG_SECRETS_URL="https://github.com/organizations/$GITHUB_ORG/settings/secrets/actions"

header "Setup Complete — Final Checklist"

if $TWO_ORG_MODE; then
  echo ""
  echo -e "  ${BOLD}Two-org isolated architecture:${NC}"
  echo -e "  ${GREEN}Governance org:${NC}   $PLATFORM_ORG  (platform-admins only)"
  echo -e "  ${GREEN}Engineering org:${NC}  $GITHUB_ORG  (all engineers)"
  echo -e "  ${GREEN}Governance repo:${NC}  $GOV_URL"
  echo -e "  ${DIM}Visibility: internal — accessible within enterprise, not public${NC}"
fi

echo ""
echo -e "${BOLD}━━━ SECRETS: Governance Repo ($PLATFORM_ORG/$GOVERNANCE_REPO) ━━━${NC}"
echo -e "${DIM}→ $GOV_SECRETS_URL${NC}"
echo ""
printf "  %-38s %s\n" "SECRET NAME" "PURPOSE"
divider
printf "  %-38s %s\n" "REPO_FACTORY_TOKEN" "PAT with repo+admin:org on $GITHUB_ORG — factory creates repos there"
printf "  %-38s %s\n" "AUDIT_REPORT_TOKEN" "PAT with read:org+read:audit_log on $GITHUB_ENTERPRISE — audit reports"

echo ""
echo -e "${BOLD}━━━ SECRETS: Engineering Org ($GITHUB_ORG) — all repos ━━━${NC}"
echo -e "${DIM}→ $ENG_SECRETS_URL${NC}"
echo ""
printf "  %-38s %s\n" "SECRET NAME" "PURPOSE"
divider
printf "  %-38s %s\n" "GOVERNANCE_READ_TOKEN" "PAT with issues:read on $PLATFORM_ORG/$GOVERNANCE_REPO only"
printf "  %-38s %s\n" "" "(used by waiver-check in every engineering repo's compliance workflow)"
printf "  %-38s %s\n" "SONAR_TOKEN"           "SonarQube auth token"
printf "  %-38s %s\n" "SONAR_HOST_URL"        "SonarQube server URL (e.g. https://sonar.meridian.io)"
printf "  %-38s %s\n" "NEXUS_IQ_URL"          "Nexus IQ server URL"
printf "  %-38s %s\n" "NEXUS_IQ_USERNAME"     "Nexus IQ service account username"
printf "  %-38s %s\n" "NEXUS_IQ_PASSWORD"     "Nexus IQ service account password"
printf "  %-38s %s\n" "STAGING_APP_URL"       "DAST target — staging env URL for ZAP scans"

echo ""
echo -e "${BOLD}━━━ REPOSITORY VARIABLE: Governance Repo ━━━${NC}"
echo -e "${DIM}→ $GOV_URL/settings/variables/actions${NC}"
echo ""
printf "  %-38s %s\n" "VARIABLE NAME" "VALUE"
divider
printf "  %-38s %s\n" "GITHUB_ORG_NAME" "$GITHUB_ORG"

if $TWO_ORG_MODE; then
  echo ""
  echo -e "${BOLD}━━━ CROSS-ORG ACCESS EXPLAINED ━━━${NC}"
  echo ""
  echo -e "  ${CYAN}Engineering repo → Governance repo (read-only):${NC}"
  echo -e "  GOVERNANCE_READ_TOKEN in $GITHUB_ORG allows compliance workflows to"
  echo -e "  check if a waiver exists in $PLATFORM_ORG/$GOVERNANCE_REPO."
  echo -e "  This PAT should have ONLY issues:read on the governance repo — nothing else."
  echo ""
  echo -e "  ${CYAN}Governance repo → Engineering org (write):${NC}"
  echo -e "  REPO_FACTORY_TOKEN in the governance repo allows factory.yml workflows"
  echo -e "  to create repos and teams in $GITHUB_ORG."
  echo -e "  This PAT should be a service account member of $PLATFORM_ORG only."
  echo ""
  echo -e "  ${CYAN}Reusable workflow cross-org reference:${NC}"
  echo -e "  Engineering repos call:"
  echo -e "  ${DIM}uses: $PLATFORM_ORG/$GOVERNANCE_REPO/.github/workflows/waiver-check.yml@main${NC}"
  echo -e "  This works because the governance repo is ${BOLD}internal${NC} (not private) —"
  echo -e "  visible to all orgs within the $GITHUB_ENTERPRISE enterprise."
fi

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
for slug in platform-admins compliance-team internal-audit; do
  if team_exists "$PLATFORM_ORG" "$slug"; then
    success "  Team (governance): $slug"
  else
    warn "  Missing team in $PLATFORM_ORG: $slug — re-run step 9"
  fi
done
if $TWO_ORG_MODE; then
  for slug in all-engineers security-reviewers; do
    if team_exists "$GITHUB_ORG" "$slug"; then
      success "  Team (engineering): $slug"
    else
      warn "  Missing team in $GITHUB_ORG: $slug — re-run step 9"
    fi
  done
fi

header "Next Steps"

cat << NEXTSTEPS
  1. Create a dedicated service-account user (e.g. meridian-governance-bot)
     Add it as a member of $PLATFORM_ORG only — NOT $GITHUB_ORG

  2. Generate two PATs from that service account:
     a) GOVERNANCE_READ_TOKEN — scope: issues:read on $PLATFORM_ORG/$GOVERNANCE_REPO only
        Set as org-level secret in $GITHUB_ORG (engineering org):
        → $ENG_SECRETS_URL

     b) REPO_FACTORY_TOKEN — scope: repo + admin:org on $GITHUB_ORG
        Set as repo-level secret in $PLATFORM_ORG/$GOVERNANCE_REPO:
        → $GOV_SECRETS_URL

  3. Generate AUDIT_REPORT_TOKEN — scope: read:org + read:audit_log
     Set as repo-level secret in $PLATFORM_ORG/$GOVERNANCE_REPO:
     → $GOV_SECRETS_URL

  4. Add current user to platform-admins team (governance org only):
     → https://github.com/orgs/$PLATFORM_ORG/teams/platform-admins

  5. Test the repo factory: $ bash governance-scripts/factory/new-repo.sh

  6. Test the team factory:  $ bash governance-scripts/factory/new-team.sh

  7. Trigger compliance report:
     $ gh workflow run waiver-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  8. Trigger audit report:
     $ gh workflow run central-audit-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  9. Verify a real PR in an engineering repo has all compliance checks running.

  10. Brief your teams on waiver requests, repo requests, and compliance reports.

NEXTSTEPS

echo -e "${BOLD}${GREEN}Setup complete. Governance framework is live at:${NC}"
echo -e "  ${BOLD}$GOV_URL${NC}"
echo ""
