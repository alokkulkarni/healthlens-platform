#!/usr/bin/env bash
# setup/05e-access-request-workflow.sh — Elevated Access / Ruleset Bypass Request system
# Engineers open a governance issue to request temporary elevated repo access.
# ALL requests require a platform-admin to /grant — there is no auto-approval.
# Grants temporary repo admin (which is a ruleset bypass actor).
# A scheduled revoke workflow removes access after the approved duration.
#
# Pushes:
#   .github/ISSUE_TEMPLATE/access-request.yml
#   .github/workflows/access-request.yml   (validate + route)
#   .github/workflows/access-approve.yml   (grant / deny)
#   .github/workflows/access-revoke.yml    (scheduled expiry cleanup)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    *) shift ;;
  esac
done

: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

# ── Issue Form ─────────────────────────────────────────────────────────────────
step "Pushing access-request issue form"

ACCESS_REQUEST_FORM='name: "🔐 Elevated Access Request"
description: "Request temporary elevated access to a repository. Requires platform-admin approval. All grants are logged, audited, and automatically revoked after the approved duration."
title: "[ACCESS REQUEST] "
labels:
  - "access-request"
  - "pending-review"
body:
  - type: markdown
    attributes:
      value: |
        ## 🔐 Elevated Access / Bypass Request
        All elevated access requests are **manually reviewed** by `platform-admins` and **automatically revoked** after the approved duration.

        - Maximum duration: **48 hours**
        - All grants are **logged and audited** in this repository
        - Emergency waivers for compliance checks should use the [Compliance Waiver template](../issues/new?template=waiver-request.yml) instead

  - type: input
    id: repository
    attributes:
      label: "Repository"
      description: "Full name of the engineering repository (org/repo)."
      placeholder: "meridian-engineering/payment-service"
    validations:
      required: true

  - type: dropdown
    id: access_type
    attributes:
      label: "Access Type Required"
      description: "Select the minimum access level needed."
      options:
        - "bypass-ruleset — push directly to protected branch (hotfix/incident)"
        - "temp-admin — repo admin rights (configure settings, secrets, webhooks)"
        - "emergency-write — push access to a repo where you only have read"
    validations:
      required: true

  - type: dropdown
    id: duration
    attributes:
      label: "Duration Required"
      description: "Access will be revoked automatically after this period."
      options:
        - "1 hour"
        - "4 hours"
        - "8 hours"
        - "24 hours"
        - "48 hours"
    validations:
      required: true

  - type: input
    id: ticket_ref
    attributes:
      label: "Incident / Change Ticket Reference"
      description: "JIRA/ServiceNow/PagerDuty ticket that authorises this access."
      placeholder: "INC-12345 or CHG-67890"
    validations:
      required: true

  - type: textarea
    id: justification
    attributes:
      label: "Business Justification"
      description: "Explain exactly what you need to do and why it cannot wait for a normal PR process."
      placeholder: "Production outage P1 — need to revert a bad deploy directly to main. INC-12345 raised."
    validations:
      required: true

  - type: checkboxes
    id: acknowledgement
    attributes:
      label: "Acknowledgement"
      options:
        - label: "I understand this access will be logged, audited, and automatically revoked."
          required: true
        - label: "I have raised or will raise a proper ticket for the underlying work."
          required: true
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/ISSUE_TEMPLATE/access-request.yml" \
  "$ACCESS_REQUEST_FORM" \
  "chore: add access-request issue form [governance-setup]"

# ── Workflow 1: Validate & Route ───────────────────────────────────────────────
step "Pushing access-request.yml (validate & route)"

ACCESS_REQUEST_WF='name: "Access Request — Validate & Route"

on:
  issues:
    types: [opened]

jobs:
  validate:
    if: contains(github.event.issue.labels.*.name, '"'"'access-request'"'"')
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

      - name: Validate and route
        uses: actions/github-script@v7
        env:
          ENG_TOKEN:    ${{ steps.eng-token.outputs.token }}
          ENG_ORG:      '"$GITHUB_ORG"'
          PLATFORM_ORG: '"$PLATFORM_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body        = context.payload.issue.body || '"''"';
            const issueNumber = context.issue.number;
            const requester   = context.payload.issue.user.login;
            const engOrg      = process.env.ENG_ORG;
            const engToken    = process.env.ENG_TOKEN;
            const platformOrg = process.env.PLATFORM_ORG;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = body.match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const repoFull    = parseField('"'"'Repository'"'"');
            const accessType  = parseField('"'"'Access Type Required'"'"');
            const duration    = parseField('"'"'Duration Required'"'"');
            const ticketRef   = parseField('"'"'Incident / Change Ticket Reference'"'"');
            const justif      = parseField('"'"'Business Justification'"'"');

            const errors = [];

            if (!repoFull) {
              errors.push('"'"'❌ **Repository** is required.'"'"');
            } else {
              const parts = repoFull.split('"'"'/'"'"');
              if (parts.length !== 2 || parts[1].trim() === '"'"''"'"') {
                errors.push(`❌ **Repository** must be in format \`org/repo\`. Got: \`${repoFull}\``);
              } else {
                const repoOrg  = parts[0].trim();
                const repoName = parts[1].trim();
                if (repoOrg !== engOrg) {
                  errors.push(`❌ Repository org \`${repoOrg}\` does not match engineering org \`${engOrg}\`. Only \`${engOrg}\` repos are supported.`);
                } else {
                  const r = await fetch(`https://api.github.com/repos/${repoOrg}/${repoName}`, {
                    headers: { Authorization: `Bearer ${engToken}`, Accept: '"'"'application/vnd.github+json'"'"' }
                  });
                  if (r.status === 404) errors.push(`❌ Repository \`${repoFull}\` does not exist.`);
                }
              }
            }

            if (!accessType) errors.push('"'"'❌ **Access Type** is required.'"'"');
            if (!duration)   errors.push('"'"'❌ **Duration** is required.'"'"');
            if (!ticketRef)  errors.push('"'"'❌ **Ticket Reference** is required.'"'"');
            if (!justif)     errors.push('"'"'❌ **Business Justification** is required.'"'"');

            // Check for existing active grant
            if (repoFull && !errors.length) {
              const existing = await github.rest.issues.listForRepo({
                ...context.repo, state: '"'"'open'"'"', labels: '"'"'access-granted'"'"', per_page: 100
              });
              const alreadyGranted = existing.data.find(issue =>
                issue.body?.includes(`<!-- access-grant:`) &&
                issue.body?.includes(requester) &&
                issue.body?.includes(repoFull.split('"'"'/'"'"')[1])
              );
              if (alreadyGranted) {
                errors.push(`⚠️ You already have an active access grant for this repository (see #${alreadyGranted.number}). Wait for it to expire before requesting again.`);
              }
            }

            await github.rest.issues.removeLabel({
              ...context.repo, issue_number: issueNumber, name: '"'"'pending-review'"'"'
            }).catch(() => {});

            if (errors.length > 0) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Validation Failed\n\n${errors.join('"'"'\n'"'"')}\n\nPlease edit the issue to correct the errors.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'validation-failed'"'"'] });
              return;
            }

            const typeEmoji = { bypass: '"'"'🚨'"'"', admin: '"'"'🔑'"'"', write: '"'"'✏️'"'"' };
            const typeKey   = accessType.startsWith('"'"'bypass'"'"') ? '"'"'bypass'"'"' : accessType.startsWith('"'"'temp-admin'"'"') ? '"'"'admin'"'"' : '"'"'write'"'"';

            await github.rest.issues.createComment({
              ...context.repo, issue_number: issueNumber,
              body: [
                `## ${typeEmoji[typeKey] || '"'"'🔐'"'"'} Access Request Validated`,
                '"'"''"'"',
                '"'"'| Field | Value |'"'"',
                '"'"'|-------|-------|'"'"',
                `| Repository | \`${repoFull}\` |`,
                `| Access type | ${accessType} |`,
                `| Duration | ${duration} |`,
                `| Ticket | ${ticketRef} |`,
                '"'"''"'"',
                `⏳ **Awaiting platform-admin approval.** A member of \`${platformOrg}/platform-admins\` must review.`,
                '"'"''"'"',
                '"'"'**Commands:**'"'"',
                '"'"'- `/grant` — approve and grant access for the requested duration'"'"',
                '"'"'- `/grant 2h` — approve for a custom duration (e.g. 2h, 4h, 24h)'"'"',
                '"'"'- `/deny <reason>` — decline the request'"'"',
                '"'"''"'"',
                `CC: @${platformOrg}/platform-admins`
              ].join('"'"'\n'"'"')
            });
            await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'needs-platform-review'"'"'] });
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/access-request.yml" \
  "$ACCESS_REQUEST_WF" \
  "chore: add access-request validate+route workflow [governance-setup]"

# ── Workflow 2: Approve / Deny ─────────────────────────────────────────────────
step "Pushing access-approve.yml (grant/deny handler)"

ACCESS_APPROVE_WF='name: "Access Request — Grant / Deny"

on:
  issue_comment:
    types: [created]

jobs:
  handle-decision:
    if: |
      contains(github.event.issue.labels.*.name, '"'"'access-request'"'"') &&
      contains(github.event.issue.labels.*.name, '"'"'needs-platform-review'"'"') &&
      (startsWith(github.event.comment.body, '"'"'/grant'"'"') || startsWith(github.event.comment.body, '"'"'/deny'"'"'))
    runs-on: ubuntu-latest
    permissions:
      issues: write
      contents: read

    steps:
      - name: Check platform-admin membership
        id: check-admin
        uses: actions/github-script@v7
        env:
          PLATFORM_ORG: '"$PLATFORM_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const commenter   = context.payload.comment.user.login;
            const platformOrg = process.env.PLATFORM_ORG;
            try {
              await github.rest.teams.getMembershipForUserInOrg({
                org: platformOrg, team_slug: '"'"'platform-admins'"'"', username: commenter
              });
              core.setOutput('"'"'is_admin'"'"', '"'"'true'"'"');
            } catch {
              core.setOutput('"'"'is_admin'"'"', '"'"'false'"'"');
              await github.rest.issues.createComment({
                ...context.repo, issue_number: context.issue.number,
                body: `⛔ @${commenter} — only members of \`'"$PLATFORM_ORG"'/platform-admins\` can grant or deny access requests.`
              });
            }

      - name: Generate engineering token
        id: eng-token
        if: steps.check-admin.outputs.is_admin == '"'"'true'"'"'
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.GOVERNANCE_APP_ID }}
          private-key: ${{ secrets.GOVERNANCE_APP_PRIVATE_KEY }}
          owner: '"$GITHUB_ORG"'

      - name: Process grant or deny
        if: steps.check-admin.outputs.is_admin == '"'"'true'"'"'
        uses: actions/github-script@v7
        env:
          ENG_TOKEN:    ${{ steps.eng-token.outputs.token }}
          ENG_ORG:      '"$GITHUB_ORG"'
          PLATFORM_ORG: '"$PLATFORM_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const comment     = context.payload.comment.body.trim();
            const commenter   = context.payload.comment.user.login;
            const issueNumber = context.issue.number;
            const issueBody   = context.payload.issue.body || '"''"';
            const engOrg      = process.env.ENG_ORG;
            const engToken    = process.env.ENG_TOKEN;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m  = issueBody.match(rx);
              const v  = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const repoFull   = parseField('"'"'Repository'"'"') || '"''"';
            const repoName   = repoFull.split('"'"'/'"'"')[1]?.trim();
            const accessType = parseField('"'"'Access Type Required'"'"') || '"''"';
            const requester  = context.payload.issue.user.login;

            if (!repoName) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: '"'"'❌ Could not parse repository name from issue. Please close and reopen a new access request.'"'"'
              });
              return;
            }

            // Determine permission level from access type
            const permission = (
              accessType.startsWith('"'"'bypass-ruleset'"'"') || accessType.startsWith('"'"'temp-admin'"'"')
            ) ? '"'"'admin'"'"' : '"'"'maintain'"'"';
            // bypass-ruleset also gets added to the org-level bypass-approved team
            const needsOrgBypass = accessType.startsWith('"'"'bypass-ruleset'"'"');

            if (comment.startsWith('"'"'/grant'"'"')) {
              // Parse custom duration from /grant 4h or /grant 24h
              const durationStr = parseField('"'"'Duration Required'"'"') || '"'"'4 hours'"'"';
              const commentDur  = comment.replace('"'"'/grant'"'"', '"'"''"'"').trim();
              const durationSrc = commentDur || durationStr;

              const durationMatch = durationSrc.match(/(\d+)\s*(h|hour|hours?)/i);
              const hours = durationMatch ? parseInt(durationMatch[1]) : 4;
              const cappedHours = Math.min(hours, 48);
              const expiryDate  = new Date(Date.now() + cappedHours * 3600 * 1000);
              const expiryISO   = expiryDate.toISOString();

              const engHeaders = {
                Authorization: `Bearer ${engToken}`,
                Accept: '"'"'application/vnd.github+json'"'"',
                '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"',
                '"'"'Content-Type'"'"': '"'"'application/json'"'"'
              };

              // Grant repo-level collaborator access
              const grantRes = await fetch(
                `https://api.github.com/repos/${engOrg}/${repoName}/collaborators/${requester}`,
                { method: '"'"'PUT'"'"', headers: engHeaders, body: JSON.stringify({ permission }) }
              );

              if (grantRes.status !== 201 && grantRes.status !== 204) {
                const err = await grantRes.text();
                await github.rest.issues.createComment({
                  ...context.repo, issue_number: issueNumber,
                  body: `❌ Failed to grant repo access (HTTP ${grantRes.status}):\n\`\`\`\n${err}\n\`\`\``
                });
                return;
              }

              // For bypass-ruleset type: also add to bypass-approved team (org-level ruleset bypass)
              let bypassTeamGranted = false;
              if (needsOrgBypass) {
                const teamRes = await fetch(
                  `https://api.github.com/orgs/${engOrg}/teams/bypass-approved/memberships/${requester}`,
                  { method: '"'"'PUT'"'"', headers: engHeaders, body: JSON.stringify({ role: '"'"'member'"'"' }) }
                );
                bypassTeamGranted = teamRes.status === 200 || teamRes.status === 201;
                if (!bypassTeamGranted) {
                  core.warning(`Could not add ${requester} to bypass-approved team (HTTP ${teamRes.status}) — repo admin still granted`);
                }
              }

              // Store structured expiry metadata as a hidden comment
              const meta = JSON.stringify({
                repo: repoName, user: requester, permission,
                bypass_team: needsOrgBypass && bypassTeamGranted,
                expires: expiryISO, granted_by: commenter,
                issue: issueNumber
              });

              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: [
                  `## ✅ Access Granted by @${commenter}`,
                  '"'"''"'"',
                  '"'"'| Field | Value |'"'"',
                  '"'"'|-------|-------|'"'"',
                  `| Repository | \`${engOrg}/${repoName}\` |`,
                  `| User | @${requester} |`,
                  `| Repo permission | \`${permission}\` |`,
                  needsOrgBypass ? `| Org-level bypass | ${bypassTeamGranted ? '"'"'✅ Added to `bypass-approved` team'"'"' : '"'"'⚠️ Team grant failed — repo admin only'"'"'} |` : '"'"''"'"',
                  `| Expires | **${expiryDate.toUTCString()}** (${cappedHours}h) |`,
                  `| Granted by | @${commenter} |`,
                  '"'"''"'"',
                  `⏰ Access will be **automatically revoked** at \`${expiryISO}\`.`,
                  '"'"''"'"',
                  `<!-- access-grant: ${meta} -->`
                ].filter(l => l !== null).join('"'"'\n'"'"')
              });

              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"' }).catch(() => {});
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'access-granted'"'"'] });

            } else if (comment.startsWith('"'"'/deny'"'"')) {
              const reason = comment.replace('"'"'/deny'"'"', '"'"''"'"').trim() || '"'"'No reason provided.'"'"';
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Access Request Denied by @${commenter}\n\n**Reason:** ${reason}\n\nIf you believe this is incorrect, contact \`'"$PLATFORM_ORG"'/platform-admins\`.`
              });
              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"' }).catch(() => {});
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'access-denied'"'"'] });
              await github.rest.issues.update({
                ...context.repo, issue_number: issueNumber, state: '"'"'closed'"'"', state_reason: '"'"'not_planned'"'"'
              });
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/access-approve.yml" \
  "$ACCESS_APPROVE_WF" \
  "chore: add access-approve workflow [governance-setup]"

# ── Workflow 3: Scheduled Revocation ──────────────────────────────────────────
step "Pushing access-revoke.yml (scheduled expiry cleanup)"

ACCESS_REVOKE_WF='name: "Access Request — Revoke Expired Access"

on:
  schedule:
    - cron: "*/15 * * * *"   # runs every 15 minutes
  workflow_dispatch:          # allow manual trigger for testing

jobs:
  revoke-expired:
    name: "Revoke Expired Access Grants"
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

      - name: Revoke expired grants
        uses: actions/github-script@v7
        env:
          ENG_TOKEN:    ${{ steps.eng-token.outputs.token }}
          ENG_ORG:      '"$GITHUB_ORG"'
          PLATFORM_ORG: '"$PLATFORM_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const engOrg   = process.env.ENG_ORG;
            const engToken = process.env.ENG_TOKEN;
            const now      = new Date();

            // Find all open issues with access-granted label
            const issues = await github.paginate(
              github.rest.issues.listForRepo,
              { ...context.repo, state: '"'"'open'"'"', labels: '"'"'access-granted'"'"', per_page: 100 }
            );
            core.info(`Found ${issues.length} open access-granted issue(s)`);

            const engHeaders = {
              Authorization:        `Bearer ${engToken}`,
              Accept:               '"'"'application/vnd.github+json'"'"',
              '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"',
              '"'"'Content-Type'"'"':           '"'"'application/json'"'"'
            };

            for (const issue of issues) {
              // Find the grant metadata comment (hidden HTML comment)
              const comments = await github.rest.issues.listComments({
                ...context.repo, issue_number: issue.number, per_page: 100
              });

              const grantComment = comments.data.find(c => c.body?.includes('"'"'<!-- access-grant:'"'"'));
              if (!grantComment) continue;

              const metaMatch = grantComment.body.match(/<!-- access-grant: (\{.*?\}) -->/s);
              if (!metaMatch) continue;

              let meta;
              try { meta = JSON.parse(metaMatch[1]); } catch { continue; }

              const expiry = new Date(meta.expires);
              if (now < expiry) {
                core.info(`Issue #${issue.number}: access for @${meta.user} on ${meta.repo} expires at ${meta.expires} — still active`);
                continue;
              }

              core.info(`Issue #${issue.number}: access for @${meta.user} on ${meta.repo} EXPIRED — revoking`);

              // Revoke repo-level collaborator access
              const revokeRes = await fetch(
                `https://api.github.com/repos/${engOrg}/${meta.repo}/collaborators/${meta.user}`,
                { method: '"'"'DELETE'"'"', headers: engHeaders }
              );
              const revokedOk = revokeRes.status === 204 || revokeRes.status === 404;

              // Revoke org-level bypass-approved team membership (if it was granted)
              let bypassTeamRevoked = '"'"'N/A'"'"';
              if (meta.bypass_team) {
                const teamRevokeRes = await fetch(
                  `https://api.github.com/orgs/${engOrg}/teams/bypass-approved/memberships/${meta.user}`,
                  { method: '"'"'DELETE'"'"', headers: engHeaders }
                );
                bypassTeamRevoked = (teamRevokeRes.status === 204 || teamRevokeRes.status === 404)
                  ? '"'"'✅ Removed from bypass-approved team'"'"'
                  : `❌ Team removal failed (HTTP ${teamRevokeRes.status})`;
              }

              const revokeStatus = revokedOk ? '"'"'✅ Revoked'"'"' : `❌ Failed (HTTP ${revokeRes.status})`;

              await github.rest.issues.createComment({
                ...context.repo, issue_number: issue.number,
                body: [
                  '"'"'## ⏰ Access Automatically Revoked'"'"',
                  '"'"''"'"',
                  '"'"'| Field | Value |'"'"',
                  '"'"'|-------|-------|'"'"',
                  `| Repository | \`${engOrg}/${meta.repo}\` |`,
                  `| User | @${meta.user} |`,
                  `| Permission removed | \`${meta.permission}\` |`,
                  `| Expired at | ${meta.expires} |`,
                  `| Repo access revocation | ${revokeStatus} |`,
                  `| Org bypass team | ${bypassTeamRevoked} |`
                ].join('"'"'\n'"'"')
              });

              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issue.number, name: '"'"'access-granted'"'"' }).catch(() => {});
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issue.number, labels: ['"'"'access-expired'"'"'] });
              await github.rest.issues.update({
                ...context.repo, issue_number: issue.number, state: '"'"'closed'"'"', state_reason: '"'"'completed'"'"'
              });

              if (!revokedOk) core.error(`Failed to revoke access for @${meta.user} on ${meta.repo}`);
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/access-revoke.yml" \
  "$ACCESS_REVOKE_WF" \
  "chore: add access-revoke scheduled workflow [governance-setup]"

success "All access request workflows pushed"
info "Raise an access request at: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO/issues/new?template=access-request.yml"
