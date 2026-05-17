#!/usr/bin/env bash
# setup/07-rulesets.sh — Create org-level branch rulesets

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${GITHUB_ORG:?Set --org}"

step "Creating org-level ruleset: baseline-security-controls"
info "This ruleset applies to ALL repos in $GITHUB_ORG — no repo can override it."

# Required status checks — these must match exact job names in compliance.yml
REQUIRED_CHECKS=$(jq -n '[
  {"context": "CodeQL / Analyze",               "integration_id": null},
  {"context": "SonarQube Analysis",             "integration_id": null},
  {"context": "Nexus IQ Policy Evaluation",     "integration_id": null},
  {"context": "Unit Tests & Coverage",          "integration_id": null},
  {"context": "Integration Tests",              "integration_id": null},
  {"context": "waiver-check",                   "integration_id": null}
]')

# Build the ruleset payload
RULESET_PAYLOAD=$(jq -n \
  --arg name "baseline-security-controls" \
  --argjson checks "$REQUIRED_CHECKS" \
  '{
    name: $name,
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: {
        include: ["~DEFAULT_BRANCH", "refs/heads/main", "refs/heads/master", "refs/heads/release"],
        exclude: []
      },
      repository_name: {
        include: ["~ALL"],
        exclude: []
      }
    },
    rules: [
      { type: "deletion" },
      { type: "non_fast_forward" },
      { type: "required_signatures" },
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: true,
          require_last_push_approval: true,
          allowed_merge_methods: ["merge", "squash", "rebase"]
        }
      },
      {
        type: "required_status_checks",
        parameters: {
          required_status_checks: $checks,
          strict_required_status_checks_policy: false
        }
      },
      { type: "required_linear_history" }
    ],
    bypass_actors: [
      {
        actor_id: 5,
        actor_type: "RepositoryRole",
        bypass_mode: "always"
      }
    ]
  }')

# Check if ruleset already exists
EXISTING_ID=$(gh api "/orgs/$GITHUB_ORG/rulesets" \
  --jq '.[] | select(.name == "baseline-security-controls") | .id' 2>/dev/null || echo "")

if [[ -n "$EXISTING_ID" ]]; then
  warn "Ruleset 'baseline-security-controls' already exists (ID: $EXISTING_ID) — updating..."
  if gh api --method PUT "/orgs/$GITHUB_ORG/rulesets/$EXISTING_ID" \
       --input - <<< "$RULESET_PAYLOAD" &>/dev/null; then
    success "Ruleset updated (ID: $EXISTING_ID)"
  else
    warn "Could not update ruleset via API — update manually in Org Settings → Rules → Rulesets"
  fi
else
  if gh api --method POST "/orgs/$GITHUB_ORG/rulesets" \
       --input - <<< "$RULESET_PAYLOAD" &>/dev/null; then
    success "Ruleset 'baseline-security-controls' created"
  else
    error "Could not create ruleset — you may need org owner rights"
    warn "Create manually: Org Settings → Rules → Rulesets → New ruleset"
    warn "Required checks: CodeQL / Analyze, SonarQube Analysis, Nexus IQ Policy Evaluation,"
    warn "                 Unit Tests & Coverage, Integration Tests, waiver-check"
  fi
fi

step "Creating governance repo protection ruleset"
info "Protects $PLATFORM_ORG/$GOVERNANCE_REPO — requires 2 platform-admin approvals"

GOVERNANCE_RULESET=$(jq -n \
  --arg repo "${GOVERNANCE_REPO}" \
  '{
    name: "governance-repo-protection",
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: {
        include: ["~DEFAULT_BRANCH"],
        exclude: []
      },
      repository_name: {
        include: [$repo],
        exclude: []
      }
    },
    rules: [
      { type: "deletion" },
      { type: "non_fast_forward" },
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 2,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: true,
          require_last_push_approval: true,
          allowed_merge_methods: ["merge", "squash"]
        }
      }
    ]
  }')

EXISTING_GOV=$(gh api "/orgs/$PLATFORM_ORG/rulesets" \
  --jq '.[] | select(.name == "governance-repo-protection") | .id' 2>/dev/null || echo "")

if [[ -n "$EXISTING_GOV" ]]; then
  gh api --method PUT "/orgs/$PLATFORM_ORG/rulesets/$EXISTING_GOV" \
    --input - <<< "$GOVERNANCE_RULESET" &>/dev/null && success "Governance ruleset updated" || warn "Could not update"
else
  gh api --method POST "/orgs/$PLATFORM_ORG/rulesets" \
    --input - <<< "$GOVERNANCE_RULESET" &>/dev/null && success "Governance repo protection ruleset created" || warn "Could not create — set manually"
fi

step "Summary"
echo ""
echo -e "  Rulesets applied to ${BOLD}$GITHUB_ORG${NC}:"
echo -e "  ${GREEN}✓${NC}  baseline-security-controls → all repos, default+main+release branches"
echo -e "  ${GREEN}✓${NC}  governance-repo-protection → $GOVERNANCE_REPO only, 2 approvals required"
echo ""
info "Verify at: https://github.com/organizations/$GITHUB_ORG/settings/rules"
