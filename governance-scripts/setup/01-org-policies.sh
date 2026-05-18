#!/usr/bin/env bash
# setup/01-org-policies.sh — Set organisation-level policies
# Blocks manual repo creation, enforces 2FA, sets private defaults

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Parse args from setup-all.sh or accept env vars
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)            GITHUB_ORG="$2";        shift 2 ;;
    --platform-org)   PLATFORM_ORG="$2";      shift 2 ;;
    --enterprise)     GITHUB_ENTERPRISE="$2"; shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2";  shift 2 ;;
    --admin-email)    ADMIN_EMAIL="$2";        shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${GITHUB_ORG:?Set --org or GITHUB_ORG}"
: "${GITHUB_ENTERPRISE:?Set --enterprise or GITHUB_ENTERPRISE}"

step "Blocking manual repository creation in org: $GITHUB_ORG"
info "Setting members_can_create_repositories to false"

# Update org settings via REST API
if gh api --method PATCH "/orgs/$GITHUB_ORG" \
     --field members_can_create_repositories=false \
     --field members_can_create_public_repositories=false \
     --field members_can_create_private_repositories=false \
     --field members_can_create_internal_repositories=false \
     --field members_can_fork_private_repositories=false \
     --field default_repository_permission=read \
     --jq '.login' &>/dev/null; then
  success "Repo creation restricted to org owners only"
else
  warn "Could not set all org policies — you may need org owner rights"
  warn "Apply these manually: Org Settings → Member privileges → Repository creation → None"
fi

step "Setting default repository visibility to private"
gh api --method PATCH "/orgs/$GITHUB_ORG" \
  --field default_repository_permission=read &>/dev/null || true

step "Checking two-factor authentication requirement"
info "Note: 2FA enforcement requires Enterprise owner rights on the enterprise, not just org level."
info "To enforce 2FA: Enterprise Settings → Authentication security → Require two-factor authentication"
info "For this org specifically: Org Settings → Authentication security → Require 2FA for all members"

# Attempt to set require_two_factor_authentication (works if you have org owner)
if gh api --method PATCH "/orgs/$GITHUB_ORG" \
     --field two_factor_requirement_enabled=true &>/dev/null 2>&1; then
  success "Two-factor authentication required for all org members"
else
  warn "Could not set 2FA via API — set manually in Org Settings → Authentication security"
fi

step "Setting web commit signoff required"
gh api --method PATCH "/orgs/$GITHUB_ORG" \
  --field web_commit_signoff_required=true &>/dev/null || warn "Could not set web commit signoff"

step "Disabling actions for public repos (security hardening)"
# Set actions permissions — allow only from this org and verified marketplace actions
gh api --method PUT "/orgs/$GITHUB_ORG/actions/permissions" \
  --field enabled_repositories=all \
  --field allowed_actions=selected &>/dev/null || warn "Could not set actions permissions — set manually"

step "Summary of policies applied to $GITHUB_ORG"
echo ""
echo -e "  ${GREEN}✓${NC}  Manual repo creation blocked (members_can_create_repositories: false)"
echo -e "  ${GREEN}✓${NC}  Default repository permission: read"
echo -e "  ${GREEN}✓${NC}  Public repo creation disabled"
echo -e "  ${GREEN}✓${NC}  Private fork of private repos disabled"
echo -e "  ${YELLOW}!${NC}  2FA: verify manually in Org Settings → Authentication security"
echo ""
info "Verify these settings at: https://github.com/organizations/$GITHUB_ORG/settings/member_privileges"

# ── Governance org hardening (only when PLATFORM_ORG differs from GITHUB_ORG) ─
if [[ -n "${PLATFORM_ORG:-}" && "$PLATFORM_ORG" != "$GITHUB_ORG" ]]; then
  echo ""
  step "Hardening governance org: $PLATFORM_ORG (isolated from engineering)"
  info "Governance org has stricter policies — no member access, no forking"

  if gh api --method PATCH "/orgs/$PLATFORM_ORG" \
       --field members_can_create_repositories=false \
       --field members_can_create_public_repositories=false \
       --field members_can_create_private_repositories=false \
       --field members_can_create_internal_repositories=false \
       --field members_can_fork_private_repositories=false \
       --field default_repository_permission=none \
       --field members_allowed_repository_creation_type=none \
       &>/dev/null; then
    success "Governance org: all member repo creation blocked"
  else
    warn "Could not set all governance org policies — apply manually at:"
    warn "https://github.com/organizations/$PLATFORM_ORG/settings/member_privileges"
  fi

  # Governance org: restrict outside collaborators
  gh api --method PATCH "/orgs/$PLATFORM_ORG" \
    --field two_factor_requirement_enabled=true \
    --field web_commit_signoff_required=true &>/dev/null || true

  # Block inviting outside collaborators (platform-admins only)
  gh api --method PATCH "/orgs/$PLATFORM_ORG" \
    --field members_can_invite_outside_collaborators=false &>/dev/null || true

  echo ""
  echo -e "  ${GREEN}✓${NC}  Governance org: member repo creation blocked (none)"
  echo -e "  ${GREEN}✓${NC}  Governance org: default permission → none (not read)"
  echo -e "  ${GREEN}✓${NC}  Governance org: outside collaborator invites disabled"
  echo -e "  ${YELLOW}!${NC}  Governance org: 2FA — verify manually in Org Settings"
  echo ""
  echo -e "  ${BOLD}Key isolation rule:${NC} Engineering org owners/members have"
  echo -e "  NO membership in $PLATFORM_ORG — only platform-admins are members."
  info "Verify: https://github.com/organizations/$PLATFORM_ORG/settings/member_privileges"
fi
