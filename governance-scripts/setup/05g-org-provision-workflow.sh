#!/usr/bin/env bash
# setup/05g-org-provision-workflow.sh
# Issue-based new engineering organisation provisioning via governance IssueOps.
#
# Engineers (or programme leads) open a GitHub Issue in the governance repo to request
# a new engineering org.  Platform-admins approve via /provision; the bootstrap workflow
# creates the org in the enterprise via the GitHub Enterprise Cloud REST API and applies
# the complete governance baseline: policies, base teams, and baseline-security-controls
# ruleset.
#
# Pre-requisite secret in governance repo: ENTERPRISE_ADMIN_TOKEN
#   A PAT (classic) owned by an enterprise owner with scope: admin:enterprise
#   OR a GitHub App with enterprise:organization_administration:write permission.
#
# Pre-requisite repository variable in governance repo: GITHUB_ENTERPRISE_SLUG
#   Set during setup-all.sh (passed via --enterprise) so workflows can reference it.
#
# Pushes 4 files:
#   .github/ISSUE_TEMPLATE/org-request.yml   — issue form
#   .github/workflows/org-request.yml        — validate & route on issue open
#   .github/workflows/org-approve.yml        — /provision / /deny commands
#   .github/workflows/org-bootstrap.yml      — create org + apply governance baseline

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
: "${GITHUB_ENTERPRISE:?Set --enterprise or GITHUB_ENTERPRISE}"

# ── Set GITHUB_ENTERPRISE_SLUG repository variable ───────────────────────────
step "Setting GITHUB_ENTERPRISE_SLUG repository variable"
if gh api --method PATCH \
     "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/actions/variables/GITHUB_ENTERPRISE_SLUG" \
     --field name="GITHUB_ENTERPRISE_SLUG" \
     --field value="$GITHUB_ENTERPRISE" &>/dev/null 2>&1; then
  success "  GITHUB_ENTERPRISE_SLUG updated → $GITHUB_ENTERPRISE"
elif gh api --method POST \
       "/repos/$PLATFORM_ORG/$GOVERNANCE_REPO/actions/variables" \
       --field name="GITHUB_ENTERPRISE_SLUG" \
       --field value="$GITHUB_ENTERPRISE" &>/dev/null 2>&1; then
  success "  GITHUB_ENTERPRISE_SLUG created → $GITHUB_ENTERPRISE"
else
  warn "  Could not set GITHUB_ENTERPRISE_SLUG variable — set manually in governance repo vars"
fi

# ── Issue Form ─────────────────────────────────────────────────────────────────
step "Pushing org request issue form"

ORG_REQUEST_FORM='name: "🏢 New Engineering Organisation Request"
description: "Request a new engineering organisation. Standard/elevated: 1 platform-admin approval. Restricted: 2 approvals required."
title: "[ORG REQUEST] "
labels:
  - "org-request"
  - "pending-review"
body:
  - type: markdown
    attributes:
      value: |
        ## 🏢 New Engineering Organisation Request

        > ⚠️ **Organisation slugs are permanent and cannot be renamed after creation.**
        > Choose carefully — the slug becomes part of every repository URL in this org.

        - 🟢 **Standard** / 🟡 **Elevated** → provisioned after **1** platform-admin `/provision` comment (~5 min).
        - 🔴 **Restricted** → requires **2 distinct** platform-admin `/provision` comments.

  - type: input
    id: org_slug
    attributes:
      label: "Organisation Slug"
      description: "Lowercase letters, digits, and hyphens only. 1–39 characters. Cannot start or end with a hyphen. PERMANENT — cannot be changed after creation."
      placeholder: "meridian-payments"
    validations:
      required: true

  - type: input
    id: display_name
    attributes:
      label: "Display Name"
      description: "Human-readable name shown in the GitHub UI."
      placeholder: "Meridian Payments"
    validations:
      required: true

  - type: input
    id: billing_email
    attributes:
      label: "Billing Email"
      description: "Email address for billing notifications for this organisation."
      placeholder: "billing@meridian.com"
    validations:
      required: true

  - type: input
    id: admin_user
    attributes:
      label: "Initial Admin GitHub Username"
      description: "GitHub username who will be added as org owner. Must already be a member of the '"$GITHUB_ENTERPRISE"' enterprise."
      placeholder: "jsmith"
    validations:
      required: true

  - type: dropdown
    id: compliance_class
    attributes:
      label: "Compliance Classification"
      description: "standard = internal tooling  |  elevated = customer-facing / user data  |  restricted = financial / PII / regulated systems"
      options:
        - "standard"
        - "elevated"
        - "restricted"
    validations:
      required: true

  - type: textarea
    id: purpose
    attributes:
      label: "Purpose & Business Justification"
      description: "Why does this organisation need to exist? What systems or teams will it host? Link to the relevant programme or business case."
      placeholder: "New payments domain org to house all card processing microservices for the Q3 digital programme (PROJ-123). Separate org required due to PCI-DSS data isolation requirements."
    validations:
      required: true

  - type: input
    id: business_unit
    attributes:
      label: "Business Unit / Programme"
      placeholder: "Digital Payments Platform"
    validations:
      required: true

  - type: input
    id: ticket_ref
    attributes:
      label: "Ticket Reference"
      description: "JIRA / ServiceNow / project reference (optional but strongly recommended for audit trail)."
      placeholder: "JIRA-1234"

  - type: input
    id: enterprise_slug
    attributes:
      label: "Enterprise Slug (leave blank for default)"
      description: "Only fill in if you need to provision in a different enterprise than the default ('"$GITHUB_ENTERPRISE"')."
      placeholder: '"$GITHUB_ENTERPRISE"'

  - type: checkboxes
    id: acknowledgements
    attributes:
      label: "Acknowledgements"
      options:
        - label: "I understand the organisation slug is permanent and cannot be renamed after creation"
          required: true
        - label: "I confirm this organisation is required for a legitimate, approved business purpose"
          required: true
        - label: "I confirm the initial admin user is already a member of the '"$GITHUB_ENTERPRISE"' enterprise"
          required: true
        - label: "I understand this organisation will be subject to all '"$GITHUB_ENTERPRISE"' governance policies: branch rulesets, compliance workflows, waiver system, and audit reporting"
          required: true
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/ISSUE_TEMPLATE/org-request.yml" \
  "$ORG_REQUEST_FORM" \
  "chore: add org request issue form [governance-setup]"

# ── Workflow 1: Validate & Route ───────────────────────────────────────────────
step "Pushing org-request.yml (validate & route)"

ORG_REQUEST_WF='name: "Org Request — Validate & Route"

on:
  issues:
    types: [opened]

jobs:
  validate-and-route:
    if: contains(github.event.issue.labels.*.name, '"'"'org-request'"'"')
    runs-on: ubuntu-latest
    permissions:
      issues: write
      contents: read

    steps:
      - name: Validate request and route to platform-admins
        uses: actions/github-script@v7
        env:
          PLATFORM_ORG:        '"$PLATFORM_ORG"'
          DEFAULT_ENTERPRISE:  '"$GITHUB_ENTERPRISE"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body        = context.payload.issue.body || '"'"''"'"';
            const issueNumber = context.issue.number;
            const platformOrg = process.env.PLATFORM_ORG;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = body.match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const orgSlug        = parseField('"'"'Organisation Slug'"'"');
            const displayName    = parseField('"'"'Display Name'"'"');
            const billingEmail   = parseField('"'"'Billing Email'"'"');
            const adminUser      = parseField('"'"'Initial Admin GitHub Username'"'"');
            const complianceClass = parseField('"'"'Compliance Classification'"'"') || '"'"'standard'"'"';
            const purpose        = parseField('"'"'Purpose & Business Justification'"'"');
            const businessUnit   = parseField('"'"'Business Unit / Programme'"'"');

            const errors = [];

            if (!orgSlug) {
              errors.push('"'"'❌ **Organisation Slug** is required.'"'"');
            } else if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(orgSlug) || orgSlug.length > 39) {
              errors.push(`❌ **Organisation Slug** \`${orgSlug}\` is invalid — must be lowercase letters, digits, and hyphens (1–39 chars, cannot start or end with a hyphen).`);
            }

            if (!displayName)   errors.push('"'"'❌ **Display Name** is required.'"'"');
            if (!billingEmail)  errors.push('"'"'❌ **Billing Email** is required.'"'"');
            else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(billingEmail))
              errors.push('"'"'❌ **Billing Email** does not look like a valid email address.'"'"');
            if (!adminUser)     errors.push('"'"'❌ **Initial Admin GitHub Username** is required.'"'"');
            if (!purpose)       errors.push('"'"'❌ **Purpose & Business Justification** is required.'"'"');
            if (!businessUnit)  errors.push('"'"'❌ **Business Unit / Programme** is required.'"'"');

            await github.rest.issues.removeLabel({
              ...context.repo, issue_number: issueNumber, name: '"'"'pending-review'"'"'
            }).catch(() => {});

            if (errors.length > 0) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Validation Failed\n\n${errors.join('"'"'\n'"'"')}\n\nPlease edit the issue to fix the errors above. A platform-admin can re-trigger validation by briefly removing and re-adding the \`org-request\` label.`
              });
              await github.rest.issues.addLabels({
                ...context.repo, issue_number: issueNumber, labels: ['"'"'validation-failed'"'"']
              });
              return;
            }

            // Check if org slug already exists on GitHub
            const checkRes = await fetch(`https://api.github.com/orgs/${orgSlug}`, {
              headers: {
                Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
                Accept: '"'"'application/vnd.github+json'"'"'
              }
            });
            if (checkRes.status === 200) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Validation Failed\n\n❌ **Organisation slug** \`${orgSlug}\` is already taken on GitHub. Choose a different, unique slug.`
              });
              await github.rest.issues.addLabels({
                ...context.repo, issue_number: issueNumber, labels: ['"'"'validation-failed'"'"']
              });
              return;
            }

            const classBadge   = { standard: '"'"'🟢'"'"', elevated: '"'"'🟡'"'"', restricted: '"'"'🔴'"'"' };
            const approvalsNeeded = complianceClass === '"'"'restricted'"'"' ? '"'"'2 distinct platform-admin approvals'"'"' : '"'"'1 platform-admin approval'"'"';

            const summary = [
              `## ${classBadge[complianceClass] || '"'"'⚪'"'"'} Validation Passed`,
              '"'"''"'"',
              '"'"'| Field | Value |'"'"',
              '"'"'|---|---|'"'"',
              `| Org Slug | \`${orgSlug}\` |`,
              `| Display Name | ${displayName} |`,
              `| Compliance Class | \`${complianceClass}\` |`,
              `| Admin | @${adminUser} |`,
              `| Business Unit | ${businessUnit} |`,
            ].join('"'"'\n'"'"');

            await github.rest.issues.createComment({
              ...context.repo, issue_number: issueNumber,
              body: `${summary}\n\n⏳ **Awaiting ${approvalsNeeded}.**\n\nA member of \`${platformOrg}/platform-admins\` must comment:\n- \`/provision\` — approve and provision the organisation\n- \`/deny <reason>\` — decline the request\n\nCC: @${platformOrg}/platform-admins`
            });
            await github.rest.issues.addLabels({
              ...context.repo, issue_number: issueNumber, labels: ['"'"'needs-platform-review'"'"']
            });
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/org-request.yml" \
  "$ORG_REQUEST_WF" \
  "chore: add org-request validate+route workflow [governance-setup]"

# ── Workflow 2: Approve / Deny ─────────────────────────────────────────────────
step "Pushing org-approve.yml (approve / deny handler)"

ORG_APPROVE_WF='name: "Org Request — Approve / Deny"

on:
  issue_comment:
    types: [created]

jobs:
  handle-decision:
    if: |
      contains(github.event.issue.labels.*.name, '"'"'org-request'"'"') &&
      contains(github.event.issue.labels.*.name, '"'"'needs-platform-review'"'"') &&
      (startsWith(github.event.comment.body, '"'"'/provision'"'"') || startsWith(github.event.comment.body, '"'"'/deny'"'"'))
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
                body: `⛔ @${commenter} — only members of \`'"$PLATFORM_ORG"'/platform-admins\` can approve or deny org provisioning requests.`
              });
            }

      - name: Process decision
        if: steps.check-admin.outputs.is_admin == '"'"'true'"'"'
        uses: actions/github-script@v7
        env:
          PLATFORM_ORG: '"$PLATFORM_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const comment     = context.payload.comment.body.trim();
            const commenter   = context.payload.comment.user.login;
            const issueNumber = context.issue.number;
            const issue       = context.payload.issue;
            const platformOrg = process.env.PLATFORM_ORG;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = (issue.body || '"'"''"'"').match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const complianceClass = parseField('"'"'Compliance Classification'"'"') || '"'"'standard'"'"';

            // ── /deny ─────────────────────────────────────────────────────────
            if (comment.startsWith('"'"'/deny'"'"')) {
              const reason = comment.replace(/^\/deny\s*/, '"'"''"'"').trim() || '"'"'No reason provided.'"'"';
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `❌ **Request denied by @${commenter}.**\n\n**Reason:** ${reason}\n\nAddress the feedback above and open a new request when ready.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:denied'"'"'] });
              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"' }).catch(() => {});
              await github.rest.issues.update({ ...context.repo, issue_number: issueNumber, state: '"'"'closed'"'"', state_reason: '"'"'not_planned'"'"' });
              return;
            }

            // ── /provision ────────────────────────────────────────────────────
            if (complianceClass === '"'"'restricted'"'"') {
              // Restricted: require 2 distinct platform-admin approvals
              const comments = await github.rest.issues.listComments({
                ...context.repo, issue_number: issueNumber, per_page: 100
              });

              const approval1Comment = comments.data.find(c => c.body?.includes('"'"'<!-- org-approval-1:'"'"'));

              if (!approval1Comment) {
                // First approval — record it in a hidden metadata comment
                await github.rest.issues.createComment({
                  ...context.repo, issue_number: issueNumber,
                  body: `✅ **First approval from @${commenter}.** (1/2 required for restricted class)\n\nA **different** platform-admin must also comment \`/provision\` to proceed with provisioning.\n\n<!-- org-approval-1: {"approver":"${commenter}","approved_at":"${new Date().toISOString()}"} -->`
                });
                await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:approved-1'"'"'] });
              } else {
                // Second approval — validate it is a different person
                let meta = {};
                try {
                  meta = JSON.parse(approval1Comment.body.match(/<!-- org-approval-1: (\{.*?\}) -->/s)?.[1] || '"'"'{}'"'"');
                } catch { /* ignore */ }

                if (meta.approver === commenter) {
                  await github.rest.issues.createComment({
                    ...context.repo, issue_number: issueNumber,
                    body: `⛔ @${commenter} — you already provided the first approval. Restricted-class orgs require **2 distinct** platform-admin approvals. A different platform-admin must comment \`/provision\`.`
                  });
                  return;
                }

                await github.rest.issues.createComment({
                  ...context.repo, issue_number: issueNumber,
                  body: `✅ **Second approval from @${commenter}.** (2/2) 🚀 Both approvals received — starting provisioning now...`
                });
                await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:provisioning'"'"'] });
                for (const lbl of ['"'"'needs-platform-review'"'"', '"'"'org-request:approved-1'"'"']) {
                  await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: lbl }).catch(() => {});
                }
              }
            } else {
              // Standard / elevated: single approval triggers provisioning
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `✅ **Approved by @${commenter}.** 🚀 Provisioning the organisation now...`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:provisioning'"'"'] });
              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"' }).catch(() => {});
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/org-approve.yml" \
  "$ORG_APPROVE_WF" \
  "chore: add org-approve workflow [governance-setup]"

# ── Workflow 3: Bootstrap New Org ──────────────────────────────────────────────
step "Pushing org-bootstrap.yml (create org + apply governance baseline)"

ORG_BOOTSTRAP_WF='name: "Org Request — Bootstrap New Organisation"

on:
  issues:
    types: [labeled]

jobs:
  bootstrap:
    if: github.event.label.name == '"'"'org-request:provisioning'"'"'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write

    steps:
      - name: Bootstrap new organisation
        uses: actions/github-script@v7
        env:
          ENTERPRISE_TOKEN:   ${{ secrets.ENTERPRISE_ADMIN_TOKEN }}
          DEFAULT_ENTERPRISE: ${{ vars.GITHUB_ENTERPRISE_SLUG }}
          PLATFORM_ORG:       '"$PLATFORM_ORG"'
          GOV_REPO:           '"$GOVERNANCE_REPO"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const enterpriseToken = process.env.ENTERPRISE_TOKEN;
            const defaultEnterprise = process.env.DEFAULT_ENTERPRISE;
            const platformOrg = process.env.PLATFORM_ORG;
            const govRepo     = process.env.GOV_REPO;
            const issueNumber = context.issue.number;
            const issue       = context.payload.issue;

            // ── Guard: token must be set ────────────────────────────────────────
            if (!enterpriseToken) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: [
                  '"'"'## ❌ Provisioning Failed: Missing Secret'"'"',
                  '"'"''"'"',
                  '"'"'`ENTERPRISE_ADMIN_TOKEN` is not set in the governance repo secrets.'"'"',
                  '"'"''"'"',
                  '"'"'**Fix:** Add the secret at:'"'"',
                  `👉 https://github.com/${platformOrg}/${govRepo}/settings/secrets/actions`,
                  '"'"''"'"',
                  '"'"'**Required scope:** A PAT (classic) owned by an enterprise owner with `admin:enterprise` scope.'"'"',
                  '"'"''"'"',
                  '"'"'Once set, re-trigger by removing and re-adding the `org-request:provisioning` label.'"'"'
                ].join('"'"'\n'"'"')
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:failed'"'"'] });
              core.setFailed('"'"'ENTERPRISE_ADMIN_TOKEN is not set'"'"');
              return;
            }

            // ── Parse issue fields ──────────────────────────────────────────────
            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = (issue.body || '"'"''"'"').match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const orgSlug         = parseField('"'"'Organisation Slug'"'"');
            const displayName     = parseField('"'"'Display Name'"'"');
            const billingEmail    = parseField('"'"'Billing Email'"'"');
            const adminUser       = parseField('"'"'Initial Admin GitHub Username'"'"');
            const complianceClass = parseField('"'"'Compliance Classification'"'"') || '"'"'standard'"'"';
            const purpose         = parseField('"'"'Purpose & Business Justification'"'"');
            const businessUnit    = parseField('"'"'Business Unit / Programme'"'"');
            const ticketRef       = parseField('"'"'Ticket Reference'"'"');
            const enterpriseOverride = parseField('"'"'Enterprise Slug (leave blank for default)'"'"');
            const enterpriseSlug  = (enterpriseOverride && enterpriseOverride.trim() && enterpriseOverride !== defaultEnterprise)
                                      ? enterpriseOverride.trim() : defaultEnterprise;

            if (!enterpriseSlug) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: '"'"'## ❌ Provisioning Failed\n\nEnterprise slug is not configured. Set the `GITHUB_ENTERPRISE_SLUG` repository variable in the governance repo or include it in the issue form.'"'"'
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:failed'"'"'] });
              core.setFailed('"'"'Enterprise slug not configured'"'"');
              return;
            }

            if (!orgSlug) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: '"'"'## ❌ Provisioning Failed\n\nCould not parse **Organisation Slug** from issue body. This should not happen — please contact platform-admins.'"'"'
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:failed'"'"'] });
              core.setFailed('"'"'Could not parse org slug'"'"');
              return;
            }

            // ── API helpers ─────────────────────────────────────────────────────
            const entHeaders = {
              Authorization:         `Bearer ${enterpriseToken}`,
              Accept:                '"'"'application/vnd.github+json'"'"',
              '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"',
              '"'"'Content-Type'"'"':          '"'"'application/json'"'"'
            };

            async function entApi(method, path, payload = null) {
              const opts = { method, headers: entHeaders };
              if (payload) opts.body = JSON.stringify(payload);
              const res  = await fetch(`https://api.github.com${path}`, opts);
              const text = await res.text();
              let data;
              try { data = JSON.parse(text); } catch { data = { raw: text }; }
              return { status: res.status, data };
            }

            const steps = [];
            const addStep = (name, status, detail = '"'"''"'"') => {
              steps.push({ name, status, detail });
              core.info(`[${status}] ${name}${detail ? '"'"': '"'"' + detail : '"'"''"'"'}`);
            };

            // ── Step 1: Create org ──────────────────────────────────────────────
            core.info(`Creating org ${orgSlug} in enterprise ${enterpriseSlug}...`);
            const createRes = await entApi('"'"'POST'"'"', `/enterprises/${enterpriseSlug}/organizations`, {
              login:        orgSlug,
              admin:        adminUser,
              profile_name: displayName,
              billing_email: billingEmail
            });

            if (createRes.status !== 201) {
              const errMsg = createRes.data?.message || JSON.stringify(createRes.data);
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: [
                  '"'"'## ❌ Org Creation Failed'"'"',
                  '"'"''"'"',
                  `**HTTP status:** ${createRes.status}`,
                  `**Error:** ${errMsg}`,
                  '"'"''"'"',
                  '"'"'**Common causes:**'"'"',
                  '"'"'- `ENTERPRISE_ADMIN_TOKEN` does not have `admin:enterprise` scope'"'"',
                  `- Enterprise slug \`${enterpriseSlug}\` is incorrect`,
                  `- Org slug \`${orgSlug}\` is already taken`,
                  `- Admin user \`@${adminUser}\` is not a member of the enterprise`,
                  '"'"''"'"',
                  '"'"'Fix the issue and re-trigger by removing and re-adding the `org-request:provisioning` label.'"'"'
                ].join('"'"'\n'"'"')
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:failed'"'"'] });
              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'org-request:provisioning'"'"' }).catch(() => {});
              core.setFailed(`Org creation failed (HTTP ${createRes.status}): ${errMsg}`);
              return;
            }
            addStep('"'"'Create organisation'"'"', '"'"'✅'"'"', `\`${orgSlug}\` created in \`${enterpriseSlug}\``);

            // Brief pause for org to initialise
            await new Promise(r => setTimeout(r, 3000));

            // ── Step 2: Apply org policies ──────────────────────────────────────
            core.info('"'"'Applying org policies...'"'"');
            const policyRes = await entApi('"'"'PATCH'"'"', `/orgs/${orgSlug}`, {
              members_can_create_repositories:          false,
              members_can_create_public_repositories:   false,
              members_can_create_private_repositories:  false,
              members_can_create_internal_repositories: false,
              members_can_fork_private_repositories:    false,
              default_repository_permission:            '"'"'read'"'"',
              web_commit_signoff_required:              true
            });
            if (policyRes.status === 200) {
              addStep('"'"'Org policies'"'"', '"'"'✅'"'"', '"'"'Repo creation blocked, default permission: read, web commit signoff required'"'"');
            } else {
              addStep('"'"'Org policies'"'"', '"'"'⚠️'"'"', `HTTP ${policyRes.status} — verify manually in org settings`);
            }

            // ── Step 3: Create base teams ───────────────────────────────────────
            core.info('"'"'Creating base teams...'"'"');
            const teamDefs = [
              { name: '"'"'platform-admins'"'"',  description: '"'"'Platform administrators — elevated access requires approval for membership'"'"', privacy: '"'"'secret'"'"' },
              { name: '"'"'senior-engineers'"'"', description: '"'"'Senior engineers — maintain access to all repositories'"'"',                   privacy: '"'"'secret'"'"' },
              { name: '"'"'all-engineers'"'"',    description: '"'"'All engineers — read access to all repositories in this org'"'"',              privacy: '"'"'closed'"'"' },
              { name: '"'"'bypass-approved'"'"',  description: '"'"'Temporary ruleset bypass actors — MUST be empty when not in active approved use'"'"', privacy: '"'"'secret'"'"' }
            ];
            const teamIds = {};
            for (const td of teamDefs) {
              const r = await entApi('"'"'POST'"'"', `/orgs/${orgSlug}/teams`, {
                name: td.name, description: td.description, privacy: td.privacy
              });
              if (r.status === 201) {
                teamIds[td.name] = r.data.id;
              } else if (r.status === 422) {
                // Already exists — fetch the ID
                const existing = await entApi('"'"'GET'"'"', `/orgs/${orgSlug}/teams/${td.name}`);
                if (existing.status === 200) teamIds[td.name] = existing.data.id;
              } else {
                core.warning(`Team ${td.name} failed (HTTP ${r.status}): ${JSON.stringify(r.data)}`);
              }
            }
            addStep('"'"'Base teams'"'"', '"'"'✅'"'"', '"'"'platform-admins, senior-engineers, all-engineers, bypass-approved'"'"');

            // ── Step 4: Add admin user to platform-admins ───────────────────────
            core.info(`Adding @${adminUser} to platform-admins as maintainer...`);
            const addAdminRes = await entApi('"'"'PUT'"'"', `/orgs/${orgSlug}/teams/platform-admins/memberships/${adminUser}`, {
              role: '"'"'maintainer'"'"'
            });
            if (addAdminRes.status === 200) {
              addStep(`@${adminUser} → platform-admins`, '"'"'✅'"'"', '"'"'Maintainer role'"'"');
            } else {
              addStep(`@${adminUser} → platform-admins`, '"'"'⚠️'"'"', `HTTP ${addAdminRes.status} — add manually`);
            }

            // ── Step 5: Create baseline-security-controls ruleset ───────────────
            core.info('"'"'Creating baseline-security-controls ruleset...'"'"');
            const rulesetPayload = {
              name:        '"'"'baseline-security-controls'"'"',
              target:      '"'"'branch'"'"',
              enforcement: '"'"'active'"'"',
              conditions:  {
                ref_name: {
                  include: ['"'"'~DEFAULT_BRANCH'"'"', '"'"'refs/heads/main'"'"', '"'"'refs/heads/release/**'"'"'],
                  exclude: []
                },
                repository_name: { include: ['"'"'~ALL'"'"'], exclude: [] }
              },
              rules: [
                { type: '"'"'deletion'"'"' },
                { type: '"'"'non_fast_forward'"'"' },
                {
                  type: '"'"'pull_request'"'"',
                  parameters: {
                    required_approving_review_count:  1,
                    dismiss_stale_reviews_on_push:    true,
                    require_code_owner_review:        true,
                    require_last_push_approval:       true,
                    required_review_thread_resolution: true
                  }
                },
                {
                  type: '"'"'required_status_checks'"'"',
                  parameters: {
                    strict_required_status_checks_policy: true,
                    required_status_checks: [
                      { context: '"'"'CodeQL / Analyze'"'"' },
                      { context: '"'"'SonarQube Analysis'"'"' },
                      { context: '"'"'Unit Tests & Coverage'"'"' },
                      { context: '"'"'Coverage Check'"'"' },
                      { context: '"'"'waiver-check'"'"' }
                    ]
                  }
                },
                { type: '"'"'required_signatures'"'"' }
              ],
              bypass_actors: [
                { actor_id: 5, actor_type: '"'"'RepositoryRole'"'"', bypass_mode: '"'"'always'"'"' }
              ]
            };

            const rulesetRes = await entApi('"'"'POST'"'"', `/orgs/${orgSlug}/rulesets`, rulesetPayload);
            if (rulesetRes.status === 201) {
              const rulesetId = rulesetRes.data.id;
              addStep('"'"'baseline-security-controls ruleset'"'"', '"'"'✅'"'"', `ID: ${rulesetId}`);

              // Wire bypass-approved team into bypass_actors
              if (teamIds['"'"'bypass-approved'"'"'] && rulesetId) {
                const current = await entApi('"'"'GET'"'"', `/orgs/${orgSlug}/rulesets/${rulesetId}`);
                if (current.status === 200) {
                  const updatedActors = [
                    ...(current.data.bypass_actors || []),
                    { actor_id: teamIds['"'"'bypass-approved'"'"'], actor_type: '"'"'Team'"'"', bypass_mode: '"'"'always'"'"' }
                  ];
                  const updateRes = await entApi('"'"'PUT'"'"', `/orgs/${orgSlug}/rulesets/${rulesetId}`, {
                    ...current.data,
                    bypass_actors: updatedActors
                  });
                  addStep(
                    '"'"'bypass-approved team → ruleset bypass actors'"'"',
                    updateRes.status === 200 ? '"'"'✅'"'"' : '"'"'⚠️'"'"',
                    updateRes.status === 200 ? '"'"''"'"' : `HTTP ${updateRes.status}`
                  );
                }
              }
            } else {
              addStep('"'"'baseline-security-controls ruleset'"'"', '"'"'⚠️'"'"',
                `HTTP ${rulesetRes.status} — create manually: https://github.com/organizations/${orgSlug}/settings/rules`);
            }

            // ── Step 6: Set GOVERNANCE_READ_TOKEN org secret placeholder ────────
            // We cannot encrypt a secret here without libsodium, so we note it as manual.
            addStep('"'"'GOVERNANCE_READ_TOKEN org secret'"'"', '"'"'⚠️ Manual'"'"', '"'"'See instructions below'"'"');

            // ── Step 7: Create governance tracking issue ────────────────────────
            core.info('"'"'Creating governance tracking issue...'"'"');
            const stepRows = steps.map(s => `| ${s.name} | ${s.status}${s.detail ? " — " + s.detail : '"'"''"'"'} |`).join('"'"'\n'"'"');

            const trackingBody = [
              `## 🏢 Org Tracking: [\`${orgSlug}\`](https://github.com/orgs/${orgSlug})`,
              '"'"''"'"',
              '"'"'| Field | Value |'"'"',
              '"'"'|---|---|'"'"',
              `| Org | [\`${orgSlug}\`](https://github.com/orgs/${orgSlug}) |`,
              `| Display Name | ${displayName} |`,
              `| Enterprise | \`${enterpriseSlug}\` |`,
              `| Compliance Class | \`${complianceClass}\` |`,
              `| Business Unit | ${businessUnit} |`,
              `| Admin | @${adminUser} |`,
              `| Requested by | @${issue.user.login} |`,
              `| Request issue | #${issueNumber} |`,
              `| Ticket | ${ticketRef || '"'"'N/A'"'"'} |`,
              `| Provisioned | ${new Date().toISOString()} |`,
              '"'"''"'"',
              '"'"'## Automated Setup Results'"'"',
              '"'"''"'"',
              '"'"'| Step | Result |'"'"',
              '"'"'|---|---|'"'"',
              stepRows,
              '"'"''"'"',
              '"'"'## ⚠️ Manual Steps Required'"'"',
              '"'"''"'"',
              `1. **Install meridian-governance-bot** in \`${orgSlug}\`:`,
              `   👉 https://github.com/apps/${platformOrg}-bot/installations/new?target_type=Organization`,
              `2. **Set org secret \`GOVERNANCE_READ_TOKEN\`** in \`${orgSlug}\`:`,
              `   👉 https://github.com/organizations/${orgSlug}/settings/secrets/actions`,
              `   - Value: a token (or App token) with \`issues:read\` on \`${platformOrg}/${govRepo}\``,
              `3. **Set org-level secrets for compliance tools** in \`${orgSlug}\`:`,
              `   \`SONAR_TOKEN\`, \`SONAR_HOST_URL\`, \`NEXUS_IQ_URL\`, \`NEXUS_IQ_USERNAME\`, \`NEXUS_IQ_PASSWORD\``,
              `4. **Verify org settings**: https://github.com/organizations/${orgSlug}/settings/member_privileges`,
              `5. **Add engineers to teams**: https://github.com/orgs/${orgSlug}/teams`,
            ].join('"'"'\n'"'"');

            let trackingIssueNumber = '"'"'(see governance repo)'"'"';
            try {
              const ti = await github.rest.issues.create({
                owner: platformOrg,
                repo:  govRepo,
                title: `[ORG TRACKING] ${orgSlug}`,
                body:  trackingBody,
                labels: ['"'"'org-request:provisioned'"'"', '"'"'governance'"'"']
              });
              trackingIssueNumber = `${platformOrg}/${govRepo}#${ti.data.number}`;
              core.info(`Tracking issue created: ${trackingIssueNumber}`);
            } catch (err) {
              core.warning(`Could not create tracking issue: ${err.message}`);
            }

            // ── Final comment on request issue ──────────────────────────────────
            const hasFailures = steps.some(s => s.status.startsWith('"'"'⚠️'"'"') || s.status.startsWith('"'"'❌'"'"'));
            const headline = hasFailures
              ? `## ✅ Organisation \`${orgSlug}\` Provisioned (with warnings)`
              : `## ✅ Organisation \`${orgSlug}\` Fully Provisioned`;

            await github.rest.issues.createComment({
              ...context.repo, issue_number: issueNumber,
              body: [
                headline,
                '"'"''"'"',
                '"'"'| Step | Result |'"'"',
                '"'"'|---|---|'"'"',
                stepRows,
                '"'"''"'"',
                '"'"'## ⚠️ Manual Steps Required Before Engineers Can Use This Org'"'"',
                '"'"''"'"',
                `**1. Install the governance bot** in \`${orgSlug}\`:`,
                `   👉 https://github.com/apps/${platformOrg}-bot/installations/new?target_type=Organization`,
                '"'"''"'"',
                `**2. Set \`GOVERNANCE_READ_TOKEN\` org secret** (so compliance workflows can query governance issues):`,
                `   👉 https://github.com/organizations/${orgSlug}/settings/secrets/actions`,
                '"'"''"'"',
                `**3. Set compliance tool secrets** (\`SONAR_TOKEN\`, \`NEXUS_IQ_URL\`, etc.) at the same URL above.`,
                '"'"''"'"',
                `**4. Verify ruleset and teams:** https://github.com/organizations/${orgSlug}/settings/rules`,
                '"'"''"'"',
                `📋 **Governance tracking:** ${trackingIssueNumber}`,
                `🔗 **New org:** https://github.com/orgs/${orgSlug}`,
                `⚙️ **Org settings:** https://github.com/organizations/${orgSlug}/settings`
              ].join('"'"'\n'"'"')
            });

            await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'org-request:provisioned'"'"'] });
            await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'org-request:provisioning'"'"' }).catch(() => {});
            await github.rest.issues.update({ ...context.repo, issue_number: issueNumber, state: '"'"'closed'"'"', state_reason: '"'"'completed'"'"' });

            core.info(`✅ Org ${orgSlug} provisioned successfully.`);
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/org-bootstrap.yml" \
  "$ORG_BOOTSTRAP_WF" \
  "chore: add org-bootstrap provisioning workflow [governance-setup]"

success "All org provisioning workflows pushed"
info "Request a new org at: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO/issues/new?template=org-request.yml"
