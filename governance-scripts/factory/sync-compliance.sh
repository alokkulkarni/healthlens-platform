#!/usr/bin/env bash
# factory/sync-compliance.sh — Push updated compliance.yml to all repos in the org
# Run this after updating .github/templates/compliance.yml in the governance repo
# Usage: bash factory/sync-compliance.sh [--dry-run] [--repo specific-repo-name]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

DRY_RUN=false
TARGET_REPO=""

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --repo)     TARGET_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

check_prereqs

: "${PLATFORM_ORG:?Set PLATFORM_ORG in $CONFIG_FILE}"
: "${GOVERNANCE_REPO:?Set GOVERNANCE_REPO in $CONFIG_FILE}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

header "Sync Compliance Workflow"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN — no changes will be made"
echo ""

step "Fetching canonical compliance.yml from governance repo"
COMPLIANCE_CONTENT=$(gh api \
  "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/contents/.github/templates/compliance.yml" \
  --jq '.content' | base64 -d)

if [[ -z "$COMPLIANCE_CONTENT" ]]; then
  error "Could not fetch compliance template. Run setup step 4 first."
  exit 1
fi
success "Fetched compliance template ($(echo "$COMPLIANCE_CONTENT" | wc -l) lines)"

# ── Get list of repos ──────────────────────────────────────────────────────────
step "Finding repositories in $GITHUB_ORG"

if [[ -n "$TARGET_REPO" ]]; then
  REPOS=("$TARGET_REPO")
  info "Targeting single repo: $TARGET_REPO"
else
  # Get all non-archived repos (paginated)
  REPOS=()
  PAGE=1
  while true; do
    BATCH=$(gh api "/orgs/$GITHUB_ORG/repos?per_page=100&page=$PAGE&type=all" \
      --jq '.[] | select(.archived == false) | .name' 2>/dev/null || echo "")
    [[ -z "$BATCH" ]] && break
    while IFS= read -r repo; do
      REPOS+=("$repo")
    done <<< "$BATCH"
    PAGE=$((PAGE + 1))
    [[ $(echo "$BATCH" | wc -l) -lt 100 ]] && break
  done
  info "Found ${#REPOS[@]} active repositories"
fi

# ── Skip repos that shouldn't have compliance.yml ─────────────────────────────
SKIP_REPOS=("$GOVERNANCE_REPO")
echo ""
info "Repos to skip (governance and infrastructure): ${SKIP_REPOS[*]}"

# ── Sync loop ──────────────────────────────────────────────────────────────────
echo ""
step "Syncing compliance.yml to all repos"

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()

for repo in "${REPOS[@]}"; do
  # Skip governance and internal repos
  if printf '%s\n' "${SKIP_REPOS[@]}" | grep -qx "$repo"; then
    info "  Skipping: $repo"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Replace the GOVERNANCE_REPO placeholder with the actual value
  FINAL_CONTENT=$(echo "$COMPLIANCE_CONTENT" | \
    sed "s|GOVERNANCE_REPO: ''|GOVERNANCE_REPO: '${PLATFORM_ORG}/${GOVERNANCE_REPO}'|g")

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${DIM}[dry-run]${NC} Would update: $GITHUB_ORG/$repo → .github/workflows/compliance.yml"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    continue
  fi

  # Check if compliance.yml already exists (get SHA for update)
  EXISTING_SHA=$(gh api "/repos/$GITHUB_ORG/$repo/contents/.github/workflows/compliance.yml" \
    --jq '.sha' 2>/dev/null || echo "")

  ENCODED=$(printf '%s' "$FINAL_CONTENT" | base64 | tr -d '\n')

  if [[ -n "$EXISTING_SHA" ]]; then
    PAYLOAD=$(jq -n \
      --arg msg "chore: update compliance workflow [governance-sync]" \
      --arg content "$ENCODED" \
      --arg sha "$EXISTING_SHA" \
      '{message: $msg, content: $content, sha: $sha, branch: "main"}')
  else
    PAYLOAD=$(jq -n \
      --arg msg "chore: add compliance workflow [governance-sync]" \
      --arg content "$ENCODED" \
      '{message: $msg, content: $content, branch: "main"}')
  fi

  if gh api --method PUT \
       "/repos/$GITHUB_ORG/$repo/contents/.github/workflows/compliance.yml" \
       --input - <<< "$PAYLOAD" &>/dev/null; then
    success "  $repo"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    error "  Failed: $repo"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST+=("$repo")
  fi

  # Gentle rate limit — 2 repos/second max
  sleep 0.5
done

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
divider
echo ""
echo -e "  ${GREEN}✓${NC}  Updated:  $SUCCESS_COUNT repos"
echo -e "  ${DIM}–${NC}  Skipped:  $SKIP_COUNT repos"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  ${RED}✗${NC}  Failed:   $FAIL_COUNT repos"
  echo ""
  echo -e "  ${RED}Failed repos (check permissions):${NC}"
  for r in "${FAIL_LIST[@]}"; do
    echo "    - $r"
  done
fi

echo ""
[[ "$DRY_RUN" == "true" ]] && info "Dry run complete. Run without --dry-run to apply changes."
[[ "$DRY_RUN" == "false" ]] && success "Sync complete."
