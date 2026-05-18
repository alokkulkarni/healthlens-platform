#!/usr/bin/env bash
# reports/waiver-status.sh — Show current waiver status across all repos
# Usage: bash reports/waiver-status.sh [--all] [--repo my-repo]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

FILTER_REPO=""
SHOW_ALL=false

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    FILTER_REPO="$2"; shift 2 ;;
    --all)     SHOW_ALL=true;    shift ;;
    *) shift ;;
  esac
done

check_prereqs

: "${PLATFORM_ORG:?Set PLATFORM_ORG in $CONFIG_FILE}"
: "${GOVERNANCE_REPO:?Set GOVERNANCE_REPO in $CONFIG_FILE}"

GOV_URL="https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO"

clear
header "Compliance Waiver Status"
echo -e "  Source: $GOV_URL"
echo -e "  Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo ""

# ── Pending waivers ────────────────────────────────────────────────────────────
step "Pending Approval"
PENDING=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=waiver-pending&state=open&per_page=50" \
  --jq '.[] | "\(.number)\t\(.title)\t\(.html_url)\t\(.created_at[:10])"' 2>/dev/null || echo "")

if [[ -z "$PENDING" ]]; then
  success "  No waivers pending approval"
else
  printf "\n  %-6s %-55s %-12s %s\n" "Issue" "Title" "Opened" "URL"
  divider
  while IFS=$'\t' read -r num title url date; do
    title_short="${title:0:52}..."
    [[ "${#title}" -le 55 ]] && title_short="$title"
    printf "  ${YELLOW}#%-5s${NC} %-55s ${DIM}%-12s${NC} ${DIM}%s${NC}\n" \
      "$num" "$title_short" "$date" "$url"
  done <<< "$PENDING"
fi

# ── Approved waivers ───────────────────────────────────────────────────────────
echo ""
step "Active Approved Waivers"
APPROVED=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=waiver-approved&state=open&per_page=100" \
  --jq '.[] | "\(.number)\t\(.title)\t\(.html_url)\t\(.created_at[:10])"' 2>/dev/null || echo "")

if [[ -z "$APPROVED" ]]; then
  success "  No active approved waivers"
else
  TODAY=$(date -u +%Y-%m-%d)

  printf "\n  %-6s %-45s %-12s %-12s %s\n" "Issue" "Title" "Opened" "Expires" "Status"
  divider
  while IFS=$'\t' read -r num title url date; do
    # Extract expiry from title
    EXPIRY=$(echo "$title" | grep -oP '\[EXPIRES:\K[^\]]+' || echo "unknown")
    CLEAN_TITLE=$(echo "$title" | sed 's/ \[EXPIRES:[^]]*\]//')
    title_short="${CLEAN_TITLE:0:42}..."
    [[ "${#CLEAN_TITLE}" -le 45 ]] && title_short="$CLEAN_TITLE"

    # Colour-code by expiry
    if [[ "$EXPIRY" == "unknown" ]]; then
      STATUS_COL="${YELLOW}"
      STATUS="⚠ no expiry"
    elif [[ "$EXPIRY" < "$TODAY" ]]; then
      STATUS_COL="${RED}"
      STATUS="✗ OVERDUE"
    elif [[ $(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$EXPIRY" +%s 2>/dev/null) -lt $(( $(date +%s) + 7*24*60*60 )) ]]; then
      STATUS_COL="${YELLOW}"
      STATUS="⚠ expiring soon"
    else
      STATUS_COL="${GREEN}"
      STATUS="✓ active"
    fi

    # Filter by repo if requested
    if [[ -n "$FILTER_REPO" ]]; then
      echo "$title $url" | grep -qi "$FILTER_REPO" || continue
    fi

    printf "  ${GREEN}#%-5s${NC} %-45s ${DIM}%-12s${NC} ${STATUS_COL}%-12s${NC} ${STATUS_COL}%s${NC}\n" \
      "$num" "$title_short" "$date" "$EXPIRY" "$STATUS"
  done <<< "$APPROVED"
fi

# ── Expiring soon (next 7 days) ────────────────────────────────────────────────
echo ""
step "Expiring in the Next 7 Days"
SOON=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=expiry-warning-sent&state=open&per_page=50" \
  --jq '.[] | "\(.number)\t\(.title)\t\(.html_url)"' 2>/dev/null || echo "")

if [[ -z "$SOON" ]]; then
  info "  No waivers in their final 7 days"
else
  while IFS=$'\t' read -r num title url; do
    EXPIRY=$(echo "$title" | grep -oP '\[EXPIRES:\K[^\]]+' || echo "unknown")
    echo -e "  ${YELLOW}⏰${NC}  #$num — $(echo "$title" | sed 's/ \[EXPIRES:[^]]*\]//') (expires $EXPIRY)"
    echo -e "     ${DIM}$url${NC}"
  done <<< "$SOON"
fi

# ── Expired / rejected this week ───────────────────────────────────────────────
if $SHOW_ALL; then
  echo ""
  step "Recently Expired / Rejected (last 14 days)"
  SINCE=$(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
          date -u -v-14d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
          date -u '+%Y-%m-%dT%H:%M:%SZ')

  for label in "waiver-expired" "waiver-rejected"; do
    CLOSED=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=$label&state=closed&since=$SINCE&per_page=20" \
      --jq '.[] | "#\(.number) \(.title[:60])"' 2>/dev/null || echo "")
    if [[ -n "$CLOSED" ]]; then
      echo -e "\n  ${BOLD}$label:${NC}"
      while IFS= read -r line; do echo "  $line"; done <<< "$CLOSED"
    fi
  done
fi

# ── Summary counts ─────────────────────────────────────────────────────────────
echo ""
divider
echo ""
PENDING_COUNT=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=waiver-pending&state=open" \
  --jq 'length' 2>/dev/null || echo "?")
APPROVED_COUNT=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=waiver-approved&state=open" \
  --jq 'length' 2>/dev/null || echo "?")
EXPIRING_COUNT=$(gh api "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/issues?labels=expiry-warning-sent&state=open" \
  --jq 'length' 2>/dev/null || echo "?")

echo -e "  ${BOLD}Summary:${NC}  Pending: ${YELLOW}$PENDING_COUNT${NC}  |  Active: ${GREEN}$APPROVED_COUNT${NC}  |  Expiring soon: ${YELLOW}$EXPIRING_COUNT${NC}"
echo ""
info "Full waiver list: $GOV_URL/issues?labels=waiver-approved"
info "Use --all to include recently expired/rejected waivers"
