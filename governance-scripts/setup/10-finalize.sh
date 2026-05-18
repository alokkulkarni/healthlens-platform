#!/usr/bin/env bash
# setup/10-finalize.sh — Print secrets checklist, verify setup, show next steps

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

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
echo -e "${BOLD}━━━ STEP A: Create GitHub App (one-time) ━━━${NC}"
echo ""
cat << 'APPSETUP'
  1. Go to: https://github.com/organizations/PLATFORM_ORG/settings/apps/new
     (replace PLATFORM_ORG with your governance org name)

  2. Name: meridian-governance-bot  (or similar)
     Homepage: https://github.com/PLATFORM_ORG/GOVERNANCE_REPO

  3. Permissions — Repository:
       Contents:       Read & Write  (push files to repos)
       Issues:         Read          (read waivers from governance repo)
       Pull requests:  Read          (PR context in waiver checks)
       Workflows:      Read & Write  (push workflow files)
     Permissions — Organisation:
       Members:        Read & Write  (manage teams)
       Administration: Read & Write  (create repos, set rulesets)
       Audit log:      Read          (central audit reports)

  4. Uncheck "Expire user authorization tokens"
     Check "Request user authorization (OAuth) during installation": NO
     Active: YES

  5. After creation — generate a private key (downloads a .pem file)
     Note down the App ID (numeric, shown at the top of the app page)

  6. Install the app on BOTH orgs:
     → Governance org: https://github.com/organizations/PLATFORM_ORG/settings/apps
     → Engineering org: https://github.com/organizations/GITHUB_ORG/settings/apps
     For each: Install → select "All repositories"
APPSETUP

echo -e "${BOLD}━━━ SECRETS: Governance Repo ($PLATFORM_ORG/$GOVERNANCE_REPO) ━━━${NC}"
echo -e "${DIM}→ $GOV_SECRETS_URL${NC}"
echo ""
printf "  %-38s %s\n" "SECRET NAME" "PURPOSE"
divider
printf "  %-38s %s\n" "GOVERNANCE_APP_ID"     "GitHub App ID (numeric, e.g. 12345)"
printf "  %-38s %s\n" "GOVERNANCE_APP_PRIVATE_KEY" "Contents of the .pem private key file"

echo ""
echo -e "${BOLD}━━━ SECRETS: Engineering Org ($GITHUB_ORG) — org-level, all repos ━━━${NC}"
echo -e "${DIM}→ $ENG_SECRETS_URL${NC}"
echo ""
printf "  %-38s %s\n" "SECRET NAME" "PURPOSE"
divider
printf "  %-38s %s\n" "GOVERNANCE_APP_ID"     "Same App ID — used by waiver-check reusable workflow"
printf "  %-38s %s\n" "GOVERNANCE_APP_PRIVATE_KEY" "Same private key — waiver-check generates short-lived token"
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
  echo -e "  GOVERNANCE_APP_ID + GOVERNANCE_APP_PRIVATE_KEY secrets in $GITHUB_ORG"
  echo -e "  allow the waiver-check workflow to generate a short-lived token (1h) scoped"
  echo -e "  to read issues in $PLATFORM_ORG/$GOVERNANCE_REPO only."
  echo ""
  echo -e "  ${CYAN}Governance repo → Engineering org (write):${NC}"
  echo -e "  The same GitHub App, when run in governance repo workflows, generates a token"
  echo -e "  scoped to $GITHUB_ORG — allowing factory.yml to create repos and teams there."
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
  1. Add yourself to platform-admins team in $PLATFORM_ORG:
     → https://github.com/orgs/$PLATFORM_ORG/teams/platform-admins

━━━ STEP A: Create GitHub App (one-time) ━━━

  2. Go to: https://github.com/organizations/$PLATFORM_ORG/settings/apps/new

     Name:     meridian-governance-bot
     Homepage: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO

     Repository permissions:
       Contents:       Read & Write   (push files to repos)
       Issues:         Read           (read waivers from governance repo)
       Pull requests:  Read           (PR context in waiver checks)
       Workflows:      Read & Write   (push workflow files)

     Organisation permissions:
       Members:        Read & Write   (manage teams)
       Administration: Read & Write   (create repos, set rulesets)
       Audit log:      Read           (central audit reports)

     Uncheck "Expire user authorization tokens"
     Check  "Active": YES
     After creation: generate a private key (.pem file) and note the App ID

  3. Install the app on BOTH orgs:
     → Governance: https://github.com/organizations/$PLATFORM_ORG/settings/apps
     → Engineering: https://github.com/organizations/$GITHUB_ORG/settings/apps
     For each: Install → select "All repositories"

━━━ STEP B: Set Secrets ━━━

  4. In $PLATFORM_ORG/$GOVERNANCE_REPO (repo secrets):
     → $GOV_SECRETS_URL
       GOVERNANCE_APP_ID          — App ID (numeric, e.g. 12345)
       GOVERNANCE_APP_PRIVATE_KEY — Contents of the .pem file

  5. In $GITHUB_ORG (org-level secrets, available to all repos):
     → $ENG_SECRETS_URL
       GOVERNANCE_APP_ID          — Same App ID
       GOVERNANCE_APP_PRIVATE_KEY — Same .pem contents
       SONAR_TOKEN                — SonarQube auth token
       SONAR_HOST_URL             — SonarQube server URL
       NEXUS_IQ_URL               — Nexus IQ server URL
       NEXUS_IQ_USERNAME          — Nexus IQ service account username
       NEXUS_IQ_PASSWORD          — Nexus IQ service account password
       STAGING_APP_URL            — DAST target staging URL

━━━ STEP C: Set Repository Variable ━━━

  6. In $PLATFORM_ORG/$GOVERNANCE_REPO (repo variables):
     → https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO/settings/variables/actions
       GITHUB_ORG_NAME = $GITHUB_ORG

━━━ STEP D: Verify ━━━

  7. Test the repo factory:  $ bash governance-scripts/factory/new-repo.sh

  8. Test the team factory:  $ bash governance-scripts/factory/new-team.sh

  9. Trigger compliance report:
     $ gh workflow run waiver-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  10. Trigger audit report:
      $ gh workflow run central-audit-report.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO

  11. Verify a real PR in an engineering repo has all compliance checks running.

  12. Brief your teams on waiver requests, repo requests, and compliance reports.

NEXTSTEPS

echo -e "${BOLD}${GREEN}Setup complete. Governance framework is live at:${NC}"
echo -e "  ${BOLD}$GOV_URL${NC}"
echo ""
