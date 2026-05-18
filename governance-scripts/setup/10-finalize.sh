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
echo -e "  ${CYAN}Open this URL to create the app:${NC}"
echo -e "  ${BOLD}https://github.com/organizations/${PLATFORM_ORG}/settings/apps/new${NC}"
echo ""
echo -e "  Fill in the form ${BOLD}exactly${NC} as follows:"
echo ""
echo -e "  ${BOLD}── Section: GitHub App name ──${NC}"
printf "  %-36s %s\n" "GitHub App name:"      "${PLATFORM_ORG}-bot"
printf "  %-36s %s\n" "Homepage URL:"         "https://github.com/${PLATFORM_ORG}/${GOVERNANCE_REPO}"
printf "  %-36s %s\n" "Description (opt.):"   "Governance automation bot for ${PLATFORM_ORG}/${GOVERNANCE_REPO}"
echo ""
echo -e "  ${BOLD}── Section: Identifying and authorizing users ──${NC}"
printf "  %-36s %s\n" "Callback URL:"         "(leave blank)"
printf "  %-36s %s\n" "Setup URL:"            "(leave blank)"
printf "  %-36s %s\n" "Expire user tokens:"   "UNCHECK  ← important"
printf "  %-36s %s\n" "Request user auth:"    "UNCHECK"
echo ""
echo -e "  ${BOLD}── Section: Post installation ──${NC}"
printf "  %-36s %s\n" "Setup URL:"            "(leave blank)"
printf "  %-36s %s\n" "Redirect on update:"   "UNCHECK"
echo ""
echo -e "  ${BOLD}── Section: Webhook ──${NC}"
printf "  %-36s %s\n" "Active:"               "UNCHECK  (no webhooks needed)"
printf "  %-36s %s\n" "Webhook URL:"          "(leave blank)"
echo ""
echo -e "  ${BOLD}── Section: Permissions → Repository permissions ──${NC}"
printf "  %-36s %s\n" "Actions:"              "Read & Write  (trigger/manage workflow runs)"
printf "  %-36s %s\n" "Administration:"       "Read & Write  (create repos, set branch rules)"
printf "  %-36s %s\n" "Checks:"               "Read & Write  (post compliance check results)"
printf "  %-36s %s\n" "Contents:"             "Read & Write  (push files, create commits)"
printf "  %-36s %s\n" "Issues:"               "Read          (read waiver issues)"
printf "  %-36s %s\n" "Metadata:"             "Read          (mandatory — auto-selected)"
printf "  %-36s %s\n" "Pull requests:"        "Read          (read PR context for waivers)"
printf "  %-36s %s\n" "Secrets:"              "Read & Write  (set repo secrets in new repos)"
printf "  %-36s %s\n" "Workflows:"            "Read & Write  (push .github/workflows/ files)"
echo ""
echo -e "  ${BOLD}── Section: Permissions → Organisation permissions ──${NC}"
printf "  %-36s %s\n" "Administration:"       "Read & Write  (create repos, manage org settings)"
printf "  %-36s %s\n" "Members:"              "Read & Write  (create/manage teams)"
printf "  %-36s %s\n" "Organisation secrets:" "Read & Write  (set org-level secrets)"
echo ""
echo -e "  ${BOLD}── Section: Permissions → Account permissions ──${NC}"
printf "  %-36s %s\n" "(none required)"       "(leave all as No access)"
echo ""
echo -e "  ${BOLD}── Section: Where can this GitHub App be installed? ──${NC}"
printf "  %-36s %s\n" "Installation:"         "Only on this account  (${PLATFORM_ORG})"
echo ""
echo -e "  ${GREEN}▶ Click: Create GitHub App${NC}"
echo ""
echo -e "  ${BOLD}── After creation ──${NC}"
echo -e "  On the app settings page that appears:"
printf "  %-36s %s\n" "App ID:"               "Note this number — you will set it as GOVERNANCE_APP_ID"
echo -e "  Scroll to ${BOLD}Private keys${NC} → click ${BOLD}Generate a private key${NC}"
printf "  %-36s %s\n" "Private key (.pem):"   "Downloaded to your machine — contents = GOVERNANCE_APP_PRIVATE_KEY"
echo ""
echo -e "  ${BOLD}── Install the app on BOTH orgs ──${NC}"
echo -e "  ${CYAN}Governance org:${NC}"
echo -e "  https://github.com/organizations/${PLATFORM_ORG}/settings/apps/${PLATFORM_ORG}-bot/installations"
echo -e "  → Install → All repositories"
echo ""
echo -e "  ${CYAN}Engineering org:${NC}"
echo -e "  https://github.com/organizations/${GITHUB_ORG}/settings/apps"
echo -e "  → Find '${PLATFORM_ORG}-bot' → Install → All repositories"
echo ""
echo -e "  ${DIM}Note: installing on the engineering org grants the app cross-org write access."
echo -e "  The token is always scoped to one org at a time via the 'owner:' field in workflows.${NC}"

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

echo -e "  ${BOLD}1. Add yourself to platform-admins team in ${PLATFORM_ORG}:${NC}"
echo -e "     ${CYAN}https://github.com/orgs/${PLATFORM_ORG}/teams/platform-admins${NC}"
echo ""
echo -e "  ${BOLD}2. Create the GitHub App${NC} — see detailed form above (STEP A)"
echo -e "     URL: ${CYAN}https://github.com/organizations/${PLATFORM_ORG}/settings/apps/new${NC}"
echo ""
echo -e "  ${BOLD}3. Install app on both orgs${NC} — see STEP A (install links above)"
echo ""
echo -e "  ${BOLD}4. Set secrets in ${PLATFORM_ORG}/${GOVERNANCE_REPO} (repo secrets):${NC}"
echo -e "     ${CYAN}${GOV_SECRETS_URL}${NC}"
printf "     %-38s %s\n" "GOVERNANCE_APP_ID"          "Numeric App ID from the app settings page"
printf "     %-38s %s\n" "GOVERNANCE_APP_PRIVATE_KEY" "Full contents of the generated .pem file"
echo ""
echo -e "  ${BOLD}5. Set secrets in ${GITHUB_ORG} (org-level secrets):${NC}"
echo -e "     ${CYAN}${ENG_SECRETS_URL}${NC}"
printf "     %-38s %s\n" "GOVERNANCE_APP_ID"          "Same App ID as above"
printf "     %-38s %s\n" "GOVERNANCE_APP_PRIVATE_KEY" "Same .pem contents as above"
printf "     %-38s %s\n" "SONAR_TOKEN"                "SonarQube auth token"
printf "     %-38s %s\n" "SONAR_HOST_URL"             "SonarQube server URL"
printf "     %-38s %s\n" "NEXUS_IQ_URL"               "Nexus IQ server URL"
printf "     %-38s %s\n" "NEXUS_IQ_USERNAME"          "Nexus IQ service account username"
printf "     %-38s %s\n" "NEXUS_IQ_PASSWORD"          "Nexus IQ service account password"
printf "     %-38s %s\n" "STAGING_APP_URL"            "DAST target staging URL for ZAP scans"
echo ""
echo -e "  ${BOLD}6. Set repo variable in ${PLATFORM_ORG}/${GOVERNANCE_REPO}:${NC}"
echo -e "     ${CYAN}https://github.com/${PLATFORM_ORG}/${GOVERNANCE_REPO}/settings/variables/actions${NC}"
printf "     %-38s %s\n" "GITHUB_ORG_NAME" "${GITHUB_ORG}"
echo ""
divider
echo -e "  ${BOLD}7.${NC}  Test the repo factory:   ${CYAN}\$ bash governance-scripts/factory/new-repo.sh${NC}"
echo -e "  ${BOLD}8.${NC}  Test the team factory:   ${CYAN}\$ bash governance-scripts/factory/new-team.sh${NC}"
echo -e "  ${BOLD}9.${NC}  Trigger compliance report:"
echo -e "       ${CYAN}\$ gh workflow run waiver-report.yml --repo ${PLATFORM_ORG}/${GOVERNANCE_REPO}${NC}"
echo -e "  ${BOLD}10.${NC} Trigger audit report:"
echo -e "       ${CYAN}\$ gh workflow run central-audit-report.yml --repo ${PLATFORM_ORG}/${GOVERNANCE_REPO}${NC}"
echo -e "  ${BOLD}11.${NC} Verify a real PR in an engineering repo has all compliance checks running."
echo -e "  ${BOLD}12.${NC} Brief your teams on waiver requests, repo requests, and compliance reports."
echo ""

echo -e "${BOLD}${GREEN}Setup complete. Governance framework is live at:${NC}"
echo -e "  ${BOLD}$GOV_URL${NC}"
echo ""
