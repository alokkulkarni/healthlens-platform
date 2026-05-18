#!/usr/bin/env bash
# reports/audit-query.sh — Interactive audit log query menu for compliance teams
# Usage: bash reports/audit-query.sh [--enterprise my-enterprise] [--org my-org]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enterprise) GITHUB_ENTERPRISE="$2"; shift 2 ;;
    --org)        GITHUB_ORG="$2";        shift 2 ;;
    *) shift ;;
  esac
done

check_prereqs

: "${GITHUB_ORG:?Set GITHUB_ORG in $CONFIG_FILE or pass --org}"

# ── Date range prompt ──────────────────────────────────────────────────────────
clear
header "Audit Log Query"
echo ""
DEFAULT_DAYS=7
optional_input "Number of days to look back" DAYS "$DEFAULT_DAYS"
SINCE=$(date -u -d "$DAYS days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -v"-${DAYS}d" '+%Y-%m-%dT%H:%M:%SZ')
echo ""
info "Query range: last $DAYS days (since $SINCE)"

# ── Helper function ────────────────────────────────────────────────────────────
run_query() {
  local phrase="$1"
  local label="$2"
  echo ""
  echo -e "${BOLD}$label${NC}"
  divider

  local result=""
  if [[ -n "${GITHUB_ENTERPRISE:-}" ]]; then
    result=$(gh api \
      "/enterprises/$GITHUB_ENTERPRISE/audit-log?phrase=$phrase%20created:>$SINCE&per_page=50" \
      --jq '.[] | "\(.created_at[:16])\t\(.actor)\t\(.action)\t\(.repo // .team // .org // "-")"' \
      2>/dev/null || echo "")
  else
    result=$(gh api \
      "/orgs/$GITHUB_ORG/audit-log?phrase=$phrase%20created:>$SINCE&per_page=50" \
      --jq '.[] | "\(.created_at[:16])\t\(.actor)\t\(.action)\t\(.repo // .team // .org // "-")"' \
      2>/dev/null || echo "")
  fi

  if [[ -z "$result" ]]; then
    echo -e "  ${DIM}No events in this period${NC}"
  else
    printf "  %-18s %-25s %-40s %s\n" "TIMESTAMP" "ACTOR" "ACTION" "TARGET"
    echo "  $(printf '%.0s─' {1..100})"
    while IFS=$'\t' read -r ts actor action target; do
      printf "  ${DIM}%-18s${NC} ${CYAN}%-25s${NC} %-40s ${DIM}%s${NC}\n" \
        "$ts" "$actor" "$action" "$target"
    done <<< "$result"
    COUNT=$(echo "$result" | wc -l | tr -d ' ')
    echo ""
    echo -e "  ${DIM}$COUNT event(s)${NC}"
  fi
}

export_csv() {
  local phrase="$1"
  local filename="audit-export-$(date +%Y%m%d-%H%M%S).csv"

  info "Exporting to $filename..."
  local result=""
  if [[ -n "${GITHUB_ENTERPRISE:-}" ]]; then
    result=$(gh api \
      "/enterprises/$GITHUB_ENTERPRISE/audit-log?phrase=$phrase%20created:>$SINCE&per_page=100" \
      --jq -r '["timestamp","actor","action","target","country","data"],
               (.[] | [.created_at[:19], .actor, .action,
                        (.repo // .team // .org // ""),
                        .country // "", tostring]) | @csv' 2>/dev/null || echo "")
  fi

  if [[ -n "$result" ]]; then
    echo "$result" > "$filename"
    success "Exported to $filename"
  else
    warn "No data to export (enterprise audit log may require GHES or EMU)"
  fi
}

# ── Menu ───────────────────────────────────────────────────────────────────────
while true; do
  echo ""
  divider
  echo -e "\n  ${BOLD}Select a query:${NC}\n"
  echo "  1.  Admin/owner changes"
  echo "  2.  Branch protection & ruleset bypasses"
  echo "  3.  New repository creation"
  echo "  4.  Secret changes (Actions / Dependabot)"
  echo "  5.  Webhook additions and removals"
  echo "  6.  Dismissed GHAS / Dependabot alerts"
  echo "  7.  App (OAuth/GitHub App) installations"
  echo "  8.  Team membership changes"
  echo "  9.  CODEOWNERS / repo settings changes"
  echo "  10. All events (broad export)"
  echo ""
  echo "  0.  Exit"
  echo ""
  read -rp "$(echo -e "  ${CYAN}Choice [1-10, 0 to exit]: ${NC}")" CHOICE

  case "$CHOICE" in
    1)
      run_query "action:org.add_member OR action:org.remove_member OR action:org.update_member" \
        "Admin / Owner Changes"
      ;;
    2)
      run_query "action:protected_branch OR action:bypass_push_rulesets OR action:bypass_branch_protections" \
        "Branch Protection & Ruleset Bypasses"
      ;;
    3)
      run_query "action:repo.create OR action:repo.transfer" \
        "New Repositories"
      ;;
    4)
      run_query "action:secret.create OR action:secret.update OR action:secret.destroy" \
        "Secret Changes"
      ;;
    5)
      run_query "action:hook.create OR action:hook.destroy OR action:hook.update" \
        "Webhook Events"
      ;;
    6)
      run_query "action:code_scanning_alert.dismissed OR action:dependabot_alert.dismissed" \
        "Dismissed Security Alerts"
      ;;
    7)
      run_query "action:integration_installation.create OR action:integration_installation.destroy" \
        "App Installations"
      ;;
    8)
      run_query "action:team.add_member OR action:team.remove_member OR action:team.change_privacy" \
        "Team Membership Changes"
      ;;
    9)
      run_query "action:repo.update_actions_settings OR action:repo.config.lock_pushes OR action:repo.change_merge_setting" \
        "Repository Settings Changes"
      ;;
    10)
      run_query "" "All Events (last $DAYS days)"
      echo ""
      read -rp "$(echo -e "  ${CYAN}Export to CSV? [y/N]: ${NC}")" EXPORT_CHOICE
      [[ "${EXPORT_CHOICE,,}" == "y" ]] && export_csv ""
      ;;
    0)
      echo ""
      info "Exiting audit query tool."
      exit 0
      ;;
    *)
      warn "Invalid choice. Enter 0-10."
      ;;
  esac

  echo ""
  read -rp "$(echo -e "  ${CYAN}Export this query to CSV? [y/N]: ${NC}")" EXPORT_CHOICE
  [[ "${EXPORT_CHOICE,,}" == "y" ]] && export_csv ""
done
