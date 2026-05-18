#!/usr/bin/env bash
# setup/05f-org-change-detection.sh — Real-time org change detection & alerting
# Pushes .github/workflows/org-change-detection.yml to the governance repo.
# Runs every 30 minutes; queries the engineering org audit log for:
#   • Ruleset create/update/delete       → CRITICAL alert
#   • Direct repo creation (not via governance issue) → WARNING
#   • Org member role change (to owner)  → CRITICAL alert
#   • Branch protection edits            → WARNING
#   • Org-level secret add/update        → WARNING
#   • Repo visibility changes            → CRITICAL alert
#   • Ruleset bypass events              → audit trail entry
# Each unique event creates a governance issue with 'org-change-alert' label.
# Deduplication: event _document_id embedded in issue body prevents re-alerting.

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
    *) shift ;;
  esac
done

: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

step "Pushing org-change-detection.yml to $PLATFORM_ORG/$GOVERNANCE_REPO"

ORG_CHANGE_DETECTION_WF='name: "Org Change Detection"

on:
  schedule:
    - cron: "*/30 * * * *"   # every 30 minutes
  workflow_dispatch:
    inputs:
      lookback_minutes:
        description: "How many minutes back to scan (default 35 — slight overlap with previous run)"
        required: false
        default: "35"

jobs:
  detect-changes:
    name: "Detect Direct Org Changes"
    runs-on: ubuntu-latest
    permissions:
      issues: write
      contents: read

    steps:
      - name: Generate engineering token
        id: eng-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.GOVERNANCE_APP_ID }}
          private-key: ${{ secrets.GOVERNANCE_APP_PRIVATE_KEY }}
          owner: '"$GITHUB_ORG"'

      - name: Scan audit log and raise alerts
        uses: actions/github-script@v7
        env:
          ENG_TOKEN:       ${{ steps.eng-token.outputs.token }}
          ENG_ORG:         '"$GITHUB_ORG"'
          PLATFORM_ORG:    '"$PLATFORM_ORG"'
          GOVERNANCE_REPO: '"$GOVERNANCE_REPO"'
          LOOKBACK_MIN:    ${{ inputs.lookback_minutes || 35 }}
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const engOrg      = process.env.ENG_ORG;
            const engToken    = process.env.ENG_TOKEN;
            const platformOrg = process.env.PLATFORM_ORG;
            const govRepo     = process.env.GOVERNANCE_REPO;
            const lookbackMin = parseInt(process.env.LOOKBACK_MIN) || 35;

            // ── Event classification ────────────────────────────────────────────
            const CRITICAL = '"'"'critical'"'"';
            const WARNING  = '"'"'warning'"'"';
            const INFO     = '"'"'info'"'"';

            const MONITORED_EVENTS = {
              // Ruleset changes — most critical (can silently disable all governance)
              '"'"'repository_ruleset.create'"'"':   { severity: WARNING,  title: '"'"'Ruleset Created'"'"',       desc: '"'"'A new branch ruleset was created directly (not via governance).'"'"' },
              '"'"'repository_ruleset.update'"'"':   { severity: CRITICAL, title: '"'"'Ruleset Modified'"'"',      desc: '"'"'An existing branch ruleset was modified. Verify no security controls were weakened.'"'"' },
              '"'"'repository_ruleset.destroy'"'"':  { severity: CRITICAL, title: '"'"'Ruleset DELETED'"'"',       desc: '"'"'🚨 A branch ruleset was deleted. Security controls may be offline.'"'"' },
              // Legacy branch protection (some repos may still use these)
              '"'"'protected_branch.create'"'"':     { severity: INFO,     title: '"'"'Branch Protection Added'"'"',   desc: '"'"'A branch protection rule was added directly.'"'"' },
              '"'"'protected_branch.update'"'"':     { severity: WARNING,  title: '"'"'Branch Protection Changed'"'"', desc: '"'"'A branch protection rule was modified outside governance.'"'"' },
              '"'"'protected_branch.destroy'"'"':    { severity: CRITICAL, title: '"'"'Branch Protection REMOVED'"'"', desc: '"'"'A branch protection rule was deleted. Branch may be unprotected.'"'"' },
              // Bypass events — someone used their bypass privilege
              '"'"'protected_branch.policy_override'"'"': { severity: WARNING, title: '"'"'Ruleset Bypass Used'"'"', desc: '"'"'Someone bypassed branch protection controls and pushed directly.'"'"' },
              // Repo creation outside governance
              '"'"'repo.create'"'"':      { severity: WARNING,  title: '"'"'Repository Created Directly'"'"', desc: '"'"'A repository was created without going through the governance issue process.'"'"' },
              // Visibility changes — could expose internal code
              '"'"'repo.visibility_change'"'"':   { severity: CRITICAL, title: '"'"'Repository Visibility Changed'"'"', desc: '"'"'🚨 A repository visibility was changed. Verify it was intentional and approved.'"'"' },
              '"'"'repo.change_private'"'"':       { severity: CRITICAL, title: '"'"'Repository Made Public'"'"',       desc: '"'"'🚨 A private repository was made public. Check for accidental exposure.'"'"' },
              // Org membership changes
              '"'"'org.add_member'"'"':    { severity: INFO,     title: '"'"'Member Added to Org'"'"',     desc: '"'"'A new member was added to the engineering org. Verify this was expected.'"'"' },
              '"'"'org.update_member'"'"': { severity: CRITICAL, title: '"'"'Member Role Changed'"'"',     desc: '"'"'🚨 A member'"'"'s role was changed (possibly to Owner). Verify this was approved.'"'"' },
              '"'"'org.remove_member'"'"': { severity: INFO,     title: '"'"'Member Removed from Org'"'"', desc: '"'"'A member was removed from the engineering org.'"'"' },
              // Org-level secrets
              '"'"'org_secret.add'"'"':    { severity: WARNING,  title: '"'"'Org Secret Added'"'"',   desc: '"'"'A new org-level secret was created. Ensure it was approved and documented.'"'"' },
              '"'"'org_secret.update'"'"': { severity: WARNING,  title: '"'"'Org Secret Updated'"'"', desc: '"'"'An org-level secret was modified.'"'"' },
              // Org-wide settings
              '"'"'org.disable_two_factor_requirement'"'"': { severity: CRITICAL, title: '"'"'2FA Requirement DISABLED'"'"', desc: '"'"'🚨 Two-factor authentication requirement was disabled for the org.'"'"' },
              // App / webhook changes
              '"'"'hook.create'"'"':           { severity: WARNING, title: '"'"'Org Webhook Created'"'"',  desc: '"'"'A new org-level webhook was created. Verify the endpoint is approved.'"'"' },
              '"'"'hook.config_changed'"'"':   { severity: WARNING, title: '"'"'Org Webhook Modified'"'"', desc: '"'"'An org webhook was modified.'"'"' },
              '"'"'integration_installation.create'"'"': { severity: WARNING, title: '"'"'GitHub App Installed'"'"', desc: '"'"'A GitHub App was installed on the org. Verify it was approved by platform-admins.'"'"' },
            };

            const severityEmoji = { [CRITICAL]: '"'"'🚨'"'"', [WARNING]: '"'"'⚠️'"'"', [INFO]: '"'"'ℹ️'"'"' };

            // ── Query the org audit log ──────────────────────────────────────────
            const since = new Date(Date.now() - lookbackMin * 60 * 1000).toISOString();

            async function queryAuditLog(action) {
              const url = `https://api.github.com/orgs/${engOrg}/audit-log?phrase=${encodeURIComponent(`action:${action}`)}&per_page=25&order=desc&include=all`;
              const res = await fetch(url, {
                headers: {
                  Authorization: `Bearer ${engToken}`,
                  Accept: '"'"'application/vnd.github+json'"'"',
                  '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"'
                }
              });
              if (!res.ok) return [];
              const data = await res.json();
              if (!Array.isArray(data)) return [];
              return data.filter(e => e.created_at && new Date(e.created_at) >= new Date(since));
            }

            // ── Find existing alert issues to deduplicate ────────────────────────
            async function isAlreadyAlerted(docId) {
              const results = await github.rest.search.issuesAndPullRequests({
                q: `repo:${platformOrg}/${govRepo} is:issue label:org-change-alert "${docId}" in:body`,
                per_page: 1
              });
              return results.data.total_count > 0;
            }

            // ── Create alert issue ───────────────────────────────────────────────
            async function createAlert(event, eventDef) {
              const docId    = event._document_id || `${event.action}-${event.created_at}`;
              const emoji    = severityEmoji[eventDef.severity];
              const actorStr = event.actor || '"'"'unknown'"'"';
              const repoStr  = event.repo  || '"'"'(org-level)'"'"';
              const ts       = event.created_at || new Date().toISOString();

              // Deduplicate
              if (await isAlreadyAlerted(docId)) {
                core.info(`Skipping duplicate alert for ${docId}`);
                return;
              }

              const isRuleset     = event.action.includes('"'"'ruleset'"'"');
              const isRepo        = event.action.startsWith('"'"'repo'"'"');
              const isMembership  = event.action.startsWith('"'"'org.'"'"');
              const isBypass      = event.action.includes('"'"'policy_override'"'"');

              const actionLinks = [];
              if (isRuleset) {
                actionLinks.push(`- 🔗 [Review current rulesets](https://github.com/organizations/${engOrg}/settings/rules)`);
              }
              if (isRepo) {
                const rName = repoStr.split('"'"'/'"'"')[1] || repoStr;
                actionLinks.push(`- 🔗 [View repository](https://github.com/${repoStr})`);
                if (!event.action.includes('"'"'visibility'"'"') && !event.action.includes('"'"'private'"'"')) {
                  actionLinks.push(`- 🔗 [Check if repo should exist in governance](https://github.com/${platformOrg}/${govRepo}/issues?q=label%3Arepo-request+is%3Aclosed)`);
                }
              }
              if (isBypass) {
                actionLinks.push(`- 🔗 [Access requests log](https://github.com/${platformOrg}/${govRepo}/issues?q=label%3Aaccess-request+is%3Aclosed)`);
              }

              const body = [
                `## ${emoji} ${eventDef.title}`,
                '"'"''"'"',
                `> ${eventDef.desc}`,
                '"'"''"'"',
                '"'"'| Field | Value |'"'"',
                '"'"'|-------|-------|'"'"',
                `| Event | \`${event.action}\` |`,
                `| Actor | @${actorStr} |`,
                `| Target | \`${repoStr}\` |`,
                `| Timestamp | \`${ts}\` |`,
                `| Severity | ${emoji} ${eventDef.severity.toUpperCase()} |`,
                '"'"''"'"',
                actionLinks.length > 0 ? '"'"'**Recommended actions:**\n'"'"' + actionLinks.join('"'"'\n'"'"') : '"'"''"'"',
                '"'"''"'"',
                `**What to check:**`,
                eventDef.severity === CRITICAL
                  ? `1. Verify this change was authorised and intended.\n2. If not: revert immediately and raise an incident.\n3. Update governance controls to prevent recurrence.\n4. Document outcome by commenting on this issue.`
                  : `1. Verify this change was expected.\n2. If unexpected, investigate and comment on this issue with findings.\n3. Close this issue once confirmed-OK or remediated.`,
                '"'"''"'"',
                `CC: @${platformOrg}/platform-admins`,
                '"'"''"'"',
                `<!-- org-change-alert: ${docId} -->`
              ].filter(l => l !== null).join('"'"'\n'"'"');

              await github.rest.issues.create({
                owner: platformOrg, repo: govRepo,
                title: `${emoji} [ORG ALERT] ${eventDef.title} — ${actorStr} — ${ts.substring(0,10)}`,
                body,
                labels: ['"'"'org-change-alert'"'"', eventDef.severity === CRITICAL ? '"'"'org-change:critical'"'"' : eventDef.severity === WARNING ? '"'"'org-change:warning'"'"' : '"'"'org-change:info'"'"']
              });

              core.warning(`${emoji} ${eventDef.severity.toUpperCase()}: ${eventDef.title} — actor: ${actorStr}, target: ${repoStr}`);
            }

            // ── Main scan loop ───────────────────────────────────────────────────
            let totalAlerts = 0;
            for (const [action, eventDef] of Object.entries(MONITORED_EVENTS)) {
              try {
                const events = await queryAuditLog(action);
                core.info(`${action}: ${events.length} event(s) in last ${lookbackMin} min`);
                for (const event of events) {
                  await createAlert(event, eventDef);
                  totalAlerts++;
                }
              } catch (err) {
                core.warning(`Could not query audit log for ${action}: ${err.message}`);
              }
            }

            if (totalAlerts === 0) {
              core.info(`✅ No concerning org changes detected in the last ${lookbackMin} minutes.`);
            } else {
              core.warning(`⚠️ ${totalAlerts} alert(s) raised — review governance issues.`);
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/org-change-detection.yml" \
  "$ORG_CHANGE_DETECTION_WF" \
  "chore: add org-change-detection workflow [governance-setup]"

success "org-change-detection.yml pushed"
info "Runs every 30 min. Trigger manually: gh workflow run org-change-detection.yml --repo $PLATFORM_ORG/$GOVERNANCE_REPO"
