#!/usr/bin/env bash
# setup/08-labels.sh — Create all required labels on the governance repository

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"

step "Creating labels on $PLATFORM_ORG/$GOVERNANCE_REPO"

# Format: "name|colour|description"
LABELS=(
  "waiver-pending|e4a11b|Waiver submitted, awaiting risk owner approval"
  "waiver-approved|1f883d|Waiver approved by risk owner"
  "waiver-rejected|cf222e|Waiver rejected"
  "waiver-expired|6e7781|Waiver expired — remediation date passed"
  "expiry-warning-sent|f0f0f0|7-day expiry warning sent"
  "compliance-report|0075ca|Auto-generated weekly waiver compliance report"
  "audit-report|8250df|Auto-generated weekly central audit report"
  "repo-provisioned|1f883d|Repository provisioned by repo factory"
  "team-provisioned|0075ca|Team created or updated by team factory"
  "governance|6e40c9|Governance and compliance related"
  "repo-request|0075ca|Repository creation request"
  "pending-review|e4a11b|Awaiting initial validation"
  "needs-platform-review|f0883e|Elevated/critical tier — requires platform-admin approval"
  "repo-request:approved|1f883d|Approved — provisioning in progress"
  "repo-request:rejected|cf222e|Repository request rejected"
  "validation-failed|d73a4a|Request failed validation checks"
  "provisioning-failed|b60205|Automated provisioning encountered an error"
  # ── Coverage labels ──────────────────────────────────────────────────────────
  "coverage-report|0075ca|Auto-maintained coverage tracking issue"
  "coverage:pass|1f883d|Coverage meets the required threshold"
  "coverage:below-threshold|cf222e|Coverage is below the required threshold"
  # ── Access request labels ────────────────────────────────────────────────────
  "access-request|8250df|Request for temporary elevated repository access"
  "access-granted|1f883d|Temporary elevated access has been granted"
  "access-denied|cf222e|Access request was denied"
  "access-expired|6e7781|Temporary access has expired and been revoked"
  # ── Org change alert labels ──────────────────────────────────────────────────
  "org-change-alert|b60205|Direct change to engineering org detected — review required"
  "org-change:critical|cf222e|Critical org change — may affect security controls"
  "org-change:warning|e4a11b|Warning-level org change requiring review"
  "org-change:info|0075ca|Informational org change — verify was expected"
  # ── Org provisioning labels ──────────────────────────────────────────────────
  "org-request|8250df|New engineering organisation provisioning request"
  "org-request:approved-1|e4a11b|First of 2 required approvals received (restricted class)"
  "org-request:provisioning|f0883e|Approved — org provisioning in progress"
  "org-request:provisioned|1f883d|Organisation provisioned and governance baseline applied"
  "org-request:denied|cf222e|Organisation request denied by platform-admins"
  "org-request:failed|b60205|Org provisioning encountered an error"
)

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name colour description <<< "$entry"
  # Delete existing then recreate (idempotent)
  gh api --method DELETE \
    "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/labels/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))" 2>/dev/null || echo "$name")" \
    &>/dev/null || true

  if gh api --method POST "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/labels" \
       --field name="$name" \
       --field color="$colour" \
       --field description="$description" &>/dev/null; then
    success "  $name"
  else
    warn "  Could not create label: $name"
  fi
done

step "Verifying labels"
ACTUAL=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/labels?per_page=50" \
  --jq '.[].name' 2>/dev/null | sort)
echo ""
echo "$ACTUAL" | while read -r l; do
  echo -e "  ${GREEN}•${NC} $l"
done
echo ""
success "Labels created on $PLATFORM_ORG/$GOVERNANCE_REPO"
info "View at: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO/labels"
