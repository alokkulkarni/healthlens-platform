#!/usr/bin/env bash
# setup-all.sh — Master orchestrator: runs full GitHub Enterprise governance setup
# Usage: bash setup-all.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

clear
echo -e "${BOLD}${MAGENTA}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║      GitHub Enterprise Governance — Full Setup Automation       ║
║      Repo Factory · Waiver System · Compliance · Audit          ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

info "This script will set up the complete governance framework described"
info "in the GitHub Enterprise Risk & Audit Governance Guide (v1.5)."
echo ""
info "What will be created:"
echo "  1. Organisation policies (block manual repo creation, enforce 2FA)"
echo "  2. Central governance repository with all workflow files"
echo "  3. Waiver system (process, check, expiry, weekly report)"
echo "  4. Compliance workflow template (pushed to all new repos)"
echo "  5. Repo Factory and Team Factory automation"
echo "  6. Central audit report workflow"
echo "  7. Organisation-level branch rulesets"
echo "  8. All required labels"
echo "  9. Base teams (platform-admins, compliance-team, etc.)"
echo " 10. Secrets checklist and next steps"
echo ""
divider

# ── Collect global config ─────────────────────────────────────────────────────
check_prereqs

# Load any previously saved config (allows resuming)
load_config

header "Global Configuration"
info "These values are saved to $CONFIG_FILE and reused by all scripts."
echo ""

# Enterprise slug
if [[ -z "${GITHUB_ENTERPRISE:-}" ]]; then
  info "Your enterprise slug appears in URLs: https://github.com/enterprises/{slug}"
  required_input "GitHub Enterprise slug (e.g. my-company)" GITHUB_ENTERPRISE
  save_config "GITHUB_ENTERPRISE" "$GITHUB_ENTERPRISE"
else
  info "Using saved enterprise: ${BOLD}$GITHUB_ENTERPRISE${NC}"
fi

# Primary engineering org
if [[ -z "${GITHUB_ORG:-}" ]]; then
  info "This is the organisation where engineering repos live."
  required_input "Primary engineering organisation name (e.g. my-company-engineering)" GITHUB_ORG
  save_config "GITHUB_ORG" "$GITHUB_ORG"
else
  info "Using saved org: ${BOLD}$GITHUB_ORG${NC}"
fi

# Platform org (where governance repo lives — may be same as engineering org)
if [[ -z "${PLATFORM_ORG:-}" ]]; then
  optional_input "Platform org (governance repo lives here; press Enter to use same as above)" PLATFORM_ORG "$GITHUB_ORG"
  save_config "PLATFORM_ORG" "$PLATFORM_ORG"
else
  info "Using saved platform org: ${BOLD}$PLATFORM_ORG${NC}"
fi

# Governance repo name
if [[ -z "${GOVERNANCE_REPO:-}" ]]; then
  optional_input "Governance repository name" GOVERNANCE_REPO "github-governance"
  save_config "GOVERNANCE_REPO" "$GOVERNANCE_REPO"
else
  info "Using saved governance repo: ${BOLD}$GOVERNANCE_REPO${NC}"
fi

# Admin contact email (for issue notifications)
if [[ -z "${ADMIN_EMAIL:-}" ]]; then
  required_input "Platform admin email (used in report notifications)" ADMIN_EMAIL
  save_config "ADMIN_EMAIL" "$ADMIN_EMAIL"
fi

echo ""
divider
echo ""
info "Configuration summary:"
echo -e "  Enterprise:       ${BOLD}$GITHUB_ENTERPRISE${NC}"
echo -e "  Engineering org:  ${BOLD}$GITHUB_ORG${NC}"
echo -e "  Platform org:     ${BOLD}$PLATFORM_ORG${NC}"
echo -e "  Governance repo:  ${BOLD}$PLATFORM_ORG/$GOVERNANCE_REPO${NC}"
echo -e "  Config saved to:  ${DIM}$CONFIG_FILE${NC}"
echo ""

# ── Verify org owner access before proceeding ─────────────────────────────────
step "Verifying org owner access"
check_org_owner "$PLATFORM_ORG"
[[ "$PLATFORM_ORG" != "$GITHUB_ORG" ]] && check_org_owner "$GITHUB_ORG"
echo ""

confirm "Proceed with full setup using these values?" || { info "Setup cancelled."; exit 0; }

# ── Step selection ─────────────────────────────────────────────────────────────
echo ""
header "Step Selection"
echo "  You can run all steps or choose specific ones to run/re-run."
echo ""
if confirm "Run ALL setup steps (recommended for first-time setup)?"; then
  STEPS="all"
else
  echo ""
  echo "  Available steps:"
  echo "    1.  Organisation policies"
  echo "    2.  Governance repository creation"
  echo "    3.  Waiver system workflows"
  echo "    4.  Compliance workflow template"
  echo "    5.  Repo Factory & Team Factory workflows"
  echo "    5b. Issue-based repo request flow"
  echo "    5c. Coverage report workflow"
  echo "    5e. Access request workflows"
  echo "    5f. Org change detection"
  echo "    5g. New org provisioning workflow"
  echo "    6.  Audit report workflow"
  echo "    7.  Branch rulesets"
  echo "    8.  Labels"
  echo "    9.  Base teams"
  echo "   10.  Secrets guide & final summary"
  echo ""
  required_input "Enter step numbers to run (comma-separated, e.g. 1,2,8)" STEPS
fi

# ── Helper to conditionally run a step ───────────────────────────────────────
run_step() {
  local step_num="$1"
  local step_name="$2"
  local script="$3"

  if [[ "$STEPS" == "all" ]] || echo "$STEPS" | grep -qw "$step_num"; then
    echo ""
    header "Step $step_num — $step_name"
    bash "$SCRIPT_DIR/setup/$script" \
      --enterprise "$GITHUB_ENTERPRISE" \
      --org "$GITHUB_ORG" \
      --platform-org "$PLATFORM_ORG" \
      --governance-repo "$GOVERNANCE_REPO" \
      --admin-email "$ADMIN_EMAIL"
    echo ""
    success "Step $step_num complete: $step_name"
  else
    info "Skipping step $step_num: $step_name"
  fi
}

# ── Run steps ──────────────────────────────────────────────────────────────────
run_step  1 "Organisation Policies"              "01-org-policies.sh"
run_step  2 "Governance Repository"              "02-governance-repo.sh"
run_step  3 "Waiver System Workflows"            "03-waiver-workflows.sh"
run_step  4 "Compliance Workflow Template"       "04-compliance-workflow.sh"
run_step  5 "Repo Factory & Team Factory"        "05-factory-workflows.sh"
run_step "5b" "Issue-Based Repo Request Flow"   "05b-repo-issue-workflow.sh"
run_step "5c" "Coverage Report Workflow"         "05c-coverage-workflow.sh"
run_step "5e" "Access Request Workflows"         "05e-access-request-workflow.sh"
run_step "5f" "Org Change Detection"             "05f-org-change-detection.sh"
run_step "5g" "New Org Provisioning Workflow"    "05g-org-provision-workflow.sh"
run_step  6 "Central Audit Report Workflow"      "06-audit-workflow.sh"
run_step  7 "Branch Rulesets"                    "07-rulesets.sh"
run_step  8 "Labels"                             "08-labels.sh"
run_step  9 "Base Teams"                         "09-base-teams.sh"
run_step 10 "Secrets Guide & Final Summary"      "10-finalize.sh"

echo ""
header "Setup Complete"
success "All selected steps have been executed."
echo ""
info "Next steps:"
echo "  1. Set the required secrets listed above in $PLATFORM_ORG/$GOVERNANCE_REPO"
echo "  2. Test by running:  bash factory/new-repo.sh"
echo "  3. Verify a new repo gets CODEOWNERS, compliance.yml, and PR template"
echo "  4. Add the first real engineer to the all-engineers team"
echo ""
info "Day-to-day commands:"
echo "  New repository:    bash governance-scripts/factory/new-repo.sh"
echo "  New team:          bash governance-scripts/factory/new-team.sh"
echo "  Sync compliance:   bash governance-scripts/factory/sync-compliance.sh"
echo "  Admin report:      bash governance-scripts/reports/admin-report.sh"
echo "  Waiver status:     bash governance-scripts/reports/waiver-status.sh"
echo "  Audit queries:     bash governance-scripts/reports/audit-query.sh"
echo ""
