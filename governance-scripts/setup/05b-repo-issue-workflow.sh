#!/usr/bin/env bash
# setup/05b-repo-issue-workflow.sh — Issue-based repo request workflow
# Engineers open a GitHub Issue (form) to request a new repo.
# Automation validates, routes by risk tier, and provisions on approval.
# Pushes: issue template, repo-request.yml, repo-approve.yml, repo-provision.yml

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
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

# ── Issue Form ─────────────────────────────────────────────────────────────────
step "Pushing repo request issue form"

REPO_REQUEST_FORM='name: "🏗️ New Repository Request"
description: "Request a new repository in the engineering organisation. Standard-tier repos are provisioned automatically. Elevated/critical require platform-admin approval."
title: "[REPO REQUEST] "
labels:
  - "repo-request"
  - "pending-review"
body:
  - type: markdown
    attributes:
      value: |
        ## 🏗️ New Repository Request
        Fill in all required fields carefully.
        - **Standard tier** repos are validated and provisioned automatically (~2 min).
        - **Elevated / Critical** tier repos require a `platform-admins` member to comment `/approve`.

  - type: input
    id: repo_name
    attributes:
      label: "Repository Name"
      description: "Lowercase letters, digits, and hyphens only. No spaces or underscores."
      placeholder: "payment-service"
    validations:
      required: true

  - type: input
    id: description
    attributes:
      label: "Description"
      description: "One-line description of what this repository does."
      placeholder: "Handles card payment processing for retail products"
    validations:
      required: true

  - type: dropdown
    id: visibility
    attributes:
      label: "Visibility"
      description: "Private is recommended for most services."
      options:
        - "private"
        - "internal"
        - "public"
    validations:
      required: true

  - type: dropdown
    id: risk_tier
    attributes:
      label: "Risk Tier"
      description: "standard = internal tooling | elevated = customer-facing / user data | critical = financial / PII systems"
      options:
        - "standard"
        - "elevated"
        - "critical"
    validations:
      required: true

  - type: input
    id: business_domain
    attributes:
      label: "Business Domain"
      description: "Domain this repository belongs to."
      placeholder: "payments"
    validations:
      required: true

  - type: input
    id: topics
    attributes:
      label: "Topics"
      description: "Comma-separated tags for discovery (optional)."
      placeholder: "java,microservice,payments"

  - type: input
    id: template
    attributes:
      label: "Starter Template"
      description: "Name of a template repo in the governance org (leave blank for empty repo)."
      placeholder: "java-service-template"

  - type: textarea
    id: team_access
    attributes:
      label: "Team Access"
      description: |
        One team per line: `team-slug: permission`
        Permissions: `read` | `triage` | `push` | `maintain` | `admin`
        `platform-admins` is added as admin automatically.
      placeholder: |
        payments-team: push
        qa-team: triage
    validations:
      required: true

  - type: textarea
    id: codeowners
    attributes:
      label: "CODEOWNERS"
      description: |
        Standard CODEOWNERS format — one rule per line: `pattern  @owner`
        Use `@org/team-slug` or `@username`. First rule should cover all files (`**`).
        `.github/**` is owned by `platform-admins` automatically.
      placeholder: |
        **  @meridian-engineering/payments-team
        src/api/**  @alokkulkarni
    validations:
      required: true

  - type: textarea
    id: justification
    attributes:
      label: "Business Justification"
      description: "Why does this repository need to exist? Link to relevant project/programme."
      placeholder: "New card processing microservice for Q3 digital programme (PROJECT-123)"
    validations:
      required: true

  - type: input
    id: public_justification
    attributes:
      label: "Public Visibility Justification"
      description: "Required only if visibility is set to public."
      placeholder: "Open-source SDK for external developer integration"
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/ISSUE_TEMPLATE/repo-request.yml" \
  "$REPO_REQUEST_FORM" \
  "chore: add repo request issue form [governance-setup]"

# ── Workflow 1: Validate & Route ───────────────────────────────────────────────
step "Pushing repo-request.yml (validate & route)"

REPO_REQUEST_WF='name: "Repo Request — Validate & Route"

on:
  issues:
    types: [opened]

jobs:
  validate-and-route:
    if: contains(github.event.issue.labels.*.name, '"'"'repo-request'"'"')
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
          ENG_TOKEN: ${{ steps.eng-token.outputs.token }}
          ENG_ORG: '"$GITHUB_ORG"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body        = context.payload.issue.body || '"''"';
            const issueNumber = context.issue.number;
            const issueAuthor = context.payload.issue.user.login;
            const engOrg      = process.env.ENG_ORG;
            const engToken    = process.env.ENG_TOKEN;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = body.match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            const repoName      = parseField('"'"'Repository Name'"'"');
            const description   = parseField('"'"'Description'"'"');
            const visibility    = parseField('"'"'Visibility'"'"') || '"'"'private'"'"';
            const riskTier      = parseField('"'"'Risk Tier'"'"') || '"'"'standard'"'"';
            const domain        = parseField('"'"'Business Domain'"'"');
            const teamAccessRaw = parseField('"'"'Team Access'"'"') || '"''"';
            const justification = parseField('"'"'Business Justification'"'"');
            const pubJust       = parseField('"'"'Public Visibility Justification'"'"');

            const errors = [];

            if (!repoName) {
              errors.push('"'"'❌ **Repository Name** is required.'"'"');
            } else if (!/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/.test(repoName)) {
              errors.push(`❌ **Repository Name** \`${repoName}\` is invalid. Use lowercase letters, digits, and hyphens only.`);
            }
            if (!description)   errors.push('"'"'❌ **Description** is required.'"'"');
            if (!domain)        errors.push('"'"'❌ **Business Domain** is required.'"'"');
            if (!justification) errors.push('"'"'❌ **Business Justification** is required.'"'"');
            if (!teamAccessRaw.trim()) errors.push('"'"'❌ **Team Access** must list at least one team.'"'"');
            if (visibility === '"'"'public'"'"' && !pubJust) errors.push('"'"'❌ **Public Visibility Justification** is required when visibility is public.'"'"');

            if (repoName && !errors.length) {
              const r = await fetch(`https://api.github.com/repos/${engOrg}/${repoName}`, {
                headers: { Authorization: `Bearer ${engToken}`, Accept: '"'"'application/vnd.github+json'"'"' }
              });
              if (r.status === 200) errors.push(`❌ Repository \`${engOrg}/${repoName}\` already exists.`);
            }

            await github.rest.issues.removeLabel({
              ...context.repo, issue_number: issueNumber, name: '"'"'pending-review'"'"'
            }).catch(() => {});

            if (errors.length > 0) {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Validation Failed\n\n${errors.join('"'"'\n'"'"')}\n\nPlease edit the issue to correct the errors above, then a platform-admin can re-trigger validation by adding the \`repo-request\` label.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'validation-failed'"'"'] });
              return;
            }

            const tierBadge = { standard: '"'"'🟢'"'"', elevated: '"'"'🟡'"'"', critical: '"'"'🔴'"'"' };
            const summary = [
              `## ${tierBadge[riskTier] || '"'"'⚪'"'"'} Validation Passed`,
              '"'"''"'"',
              '"'"'| Field | Value |'"'"',
              '"'"'|---|---|'"'"',
              `| Repository | \`${engOrg}/${repoName}\` |`,
              `| Description | ${description} |`,
              `| Visibility | \`${visibility}\` |`,
              `| Risk Tier | \`${riskTier}\` |`,
              `| Domain | ${domain} |`,
            ].join('"'"'\n'"'"');

            if (riskTier === '"'"'standard'"'"') {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `${summary}\n\n🚀 **Standard tier — auto-approving.** Provisioning will begin within seconds.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'repo-request:approved'"'"'] });
            } else {
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `${summary}\n\n⏳ **${riskTier.charAt(0).toUpperCase() + riskTier.slice(1)} tier — platform-admin review required.**\n\nA member of \`platform-admins\` must comment:\n- \`/approve\` to provision the repository\n- \`/reject <reason>\` to decline the request\n\nCC: @'"$PLATFORM_ORG"'/platform-admins`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'needs-platform-review'"'"'] });
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/repo-request.yml" \
  "$REPO_REQUEST_WF" \
  "chore: add repo-request validate+route workflow [governance-setup]"

# ── Workflow 2: Approve / Reject ───────────────────────────────────────────────
step "Pushing repo-approve.yml (approval handler)"

REPO_APPROVE_WF='name: "Repo Request — Approve / Reject"

on:
  issue_comment:
    types: [created]

jobs:
  handle-decision:
    if: |
      contains(github.event.issue.labels.*.name, '"'"'repo-request'"'"') &&
      contains(github.event.issue.labels.*.name, '"'"'needs-platform-review'"'"') &&
      (startsWith(github.event.comment.body, '"'"'/approve'"'"') || startsWith(github.event.comment.body, '"'"'/reject'"'"'))
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
            } catch (e) {
              core.setOutput('"'"'is_admin'"'"', '"'"'false'"'"');
              await github.rest.issues.createComment({
                ...context.repo, issue_number: context.issue.number,
                body: `⛔ @${commenter} — only members of \`'"$PLATFORM_ORG"'/platform-admins\` can approve or reject repo requests.`
              });
            }

      - name: Process decision
        if: steps.check-admin.outputs.is_admin == '"'"'true'"'"'
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const comment     = context.payload.comment.body.trim();
            const commenter   = context.payload.comment.user.login;
            const issueNumber = context.issue.number;

            if (comment.startsWith('"'"'/approve'"'"')) {
              await github.rest.issues.addLabels({
                ...context.repo, issue_number: issueNumber, labels: ['"'"'repo-request:approved'"'"']
              });
              await github.rest.issues.removeLabel({
                ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"'
              }).catch(() => {});
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `✅ **Approved by @${commenter}.** Provisioning the repository now...`
              });
            } else if (comment.startsWith('"'"'/reject'"'"')) {
              const reason = comment.replace('"'"'/reject'"'"', '"'"''"'"').trim() || '"'"'No reason provided.'"'"';
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `❌ **Rejected by @${commenter}.**\n\n**Reason:** ${reason}\n\nPlease address the feedback and open a new request when ready.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'repo-request:rejected'"'"'] });
              await github.rest.issues.removeLabel({ ...context.repo, issue_number: issueNumber, name: '"'"'needs-platform-review'"'"' }).catch(() => {});
              await github.rest.issues.update({
                ...context.repo, issue_number: issueNumber, state: '"'"'closed'"'"', state_reason: '"'"'not_planned'"'"'
              });
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/repo-approve.yml" \
  "$REPO_APPROVE_WF" \
  "chore: add repo-approve workflow [governance-setup]"

# ── Workflow 3: Provision ──────────────────────────────────────────────────────
step "Pushing repo-provision.yml (provisioner)"

REPO_PROVISION_WF='name: "Repo Request — Provision"

on:
  issues:
    types: [labeled]

jobs:
  provision:
    if: github.event.label.name == '"'"'repo-request:approved'"'"'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write

    steps:
      - uses: actions/checkout@v4

      - name: Generate engineering app token
        id: eng-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.GOVERNANCE_APP_ID }}
          private-key: ${{ secrets.GOVERNANCE_APP_PRIVATE_KEY }}
          owner: '"$GITHUB_ORG"'

      - name: Install js-yaml
        run: npm install js-yaml
        working-directory: ${{ github.workspace }}

      - name: Provision repository
        uses: actions/github-script@v7
        env:
          ENG_TOKEN: ${{ steps.eng-token.outputs.token }}
          ENG_ORG:   '"$GITHUB_ORG"'
          GOV_ORG:   '"$PLATFORM_ORG"'
          GOV_REPO:  '"$GOVERNANCE_REPO"'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const body        = context.payload.issue.body || '"''"';
            const issueNumber = context.issue.number;
            const issueAuthor = context.payload.issue.user.login;
            const engOrg      = process.env.ENG_ORG;
            const engToken    = process.env.ENG_TOKEN;
            const govOrg      = process.env.GOV_ORG;
            const govRepo     = process.env.GOV_REPO;

            function parseField(label) {
              const rx = new RegExp(`### ${label}\\s*\\n+([\\s\\S]*?)(?=\\n### |$)`, '"'"'i'"'"');
              const m = body.match(rx);
              const v = m ? m[1].trim() : null;
              return (!v || v === '"'"'_No response_'"'"') ? null : v;
            }

            async function engApi(method, path, payload = null) {
              const opts = {
                method,
                headers: {
                  Authorization: `Bearer ${engToken}`,
                  Accept: '"'"'application/vnd.github+json'"'"',
                  '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"',
                  '"'"'Content-Type'"'"': '"'"'application/json'"'"'
                }
              };
              if (payload) opts.body = JSON.stringify(payload);
              const res  = await fetch(`https://api.github.com${path}`, opts);
              const text = await res.text();
              return { status: res.status, data: text ? JSON.parse(text) : {} };
            }

            async function upsertFile(repo, filePath, content, msg) {
              const encoded  = Buffer.from(content).toString('"'"'base64'"'"');
              const existing = await engApi('"'"'GET'"'"', `/repos/${engOrg}/${repo}/contents/${filePath}`);
              const body     = { message: msg, content: encoded, branch: '"'"'main'"'"' };
              if (existing.status === 200) body.sha = existing.data.sha;
              return engApi('"'"'PUT'"'"', `/repos/${engOrg}/${repo}/contents/${filePath}`, body);
            }

            // ── Parse fields ─────────────────────────────────────────────────
            const repoName      = parseField('"'"'Repository Name'"'"');
            const description   = parseField('"'"'Description'"'"') || '"''"';
            const visibility    = parseField('"'"'Visibility'"'"') || '"'"'private'"'"';
            const riskTier      = parseField('"'"'Risk Tier'"'"') || '"'"'standard'"'"';
            const domain        = parseField('"'"'Business Domain'"'"') || '"''"';
            const topicsRaw     = parseField('"'"'Topics'"'"') || '"''"';
            const template      = parseField('"'"'Starter Template'"'"');
            const teamAccessRaw = parseField('"'"'Team Access'"'"') || '"''"';
            const codeownersRaw = parseField('"'"'CODEOWNERS'"'"') || '"''"';

            if (!repoName) {
              core.setFailed('"'"'Could not parse Repository Name from issue body.'"'"');
              return;
            }

            const topics = topicsRaw
              ? topicsRaw.split('"'"','"'"').map(t => t.trim().toLowerCase()).filter(Boolean)
              : [];

            const teamAccess = teamAccessRaw.split('"'"'\n'"'"')
              .map(l => l.trim()).filter(Boolean)
              .map(l => {
                const idx  = l.indexOf('"'"':'"'"');
                const team = idx >= 0 ? l.substring(0, idx).trim() : l.trim();
                const perm = idx >= 0 ? l.substring(idx + 1).trim() : '"'"'push'"'"';
                return { team, permission: perm || '"'"'push'"'"' };
              });

            if (!teamAccess.find(t => t.team === '"'"'platform-admins'"'"')) {
              teamAccess.unshift({ team: '"'"'platform-admins'"'"', permission: '"'"'admin'"'"' });
            }

            try {
              // ── 1. Create repository ────────────────────────────────────────
              core.info(`Creating ${engOrg}/${repoName}`);
              if (template) {
                await engApi('"'"'POST'"'"', `/repos/${govOrg}/${template}/generate`, {
                  owner: engOrg, name: repoName, description,
                  private: visibility !== '"'"'public'"'"', include_all_branches: false
                });
              } else {
                const r = await engApi('"'"'POST'"'"', `/orgs/${engOrg}/repos`, {
                  name: repoName, description, visibility,
                  private: visibility !== '"'"'public'"'"',
                  has_issues: true, has_projects: false, has_wiki: false,
                  delete_branch_on_merge: true, auto_init: true
                });
                if (r.status !== 201 && r.status !== 422)
                  throw new Error(`Repo create failed (HTTP ${r.status}): ${JSON.stringify(r.data)}`);
              }
              await new Promise(res => setTimeout(res, 3000));

              // ── 2. Topics ───────────────────────────────────────────────────
              if (topics.length) {
                await engApi('"'"'PUT'"'"', `/repos/${engOrg}/${repoName}/topics`, { names: topics });
              }

              // ── 3. Team access ──────────────────────────────────────────────
              for (const t of teamAccess) {
                await engApi('"'"'PUT'"'"', `/orgs/${engOrg}/teams/${t.team}/repos/${engOrg}/${repoName}`, { permission: t.permission });
              }

              // ── 4. CODEOWNERS ───────────────────────────────────────────────
              const codeownersLines = [
                `# CODEOWNERS — auto-generated by repo-factory`,
                `# Repository: ${engOrg}/${repoName}  |  Requested by: @${issueAuthor}`,
                '"'"''"'"',
                `# Governance files are always owned by platform-admins`,
                `.github/**    @${govOrg}/platform-admins`,
                '"'"''"'"',
                ...codeownersRaw.split('"'"'\n'"'"').map(l => l.trim()).filter(Boolean)
              ];
              await upsertFile(repoName, '"'"'.github/CODEOWNERS'"'"',
                codeownersLines.join('"'"'\n'"'"'),
                '"'"'chore: add CODEOWNERS [repo-factory]'"'"');

              // ── 5. Compliance workflow ──────────────────────────────────────
              const tmpl = await engApi('"'"'GET'"'"', `/repos/${govOrg}/${govRepo}/contents/.github/templates/compliance.yml`);
              if (tmpl.status === 200) {
                const compContent = Buffer.from(tmpl.data.content, '"'"'base64'"'"').toString('"'"'utf8'"'"')
                  .replace(/GOVERNANCE_REPO: '"'"''"'"'/g, `GOVERNANCE_REPO: '"'"'${govOrg}/${govRepo}'"'"'`);
                await upsertFile(repoName, '"'"'.github/workflows/compliance.yml'"'"', compContent, '"'"'chore: add compliance workflow [repo-factory]'"'"');
              }

              // ── 6. PR template ──────────────────────────────────────────────
              const prTemplate = [
                '"'"'## What does this PR do?'"'"', '"'"''"'"',
                '"'"'<!-- Describe the change -->'"'"', '"'"''"'"',
                '"'"'## Checklist'"'"', '"'"''"'"',
                '"'"'- [ ] Tests added for new behaviour'"'"',
                '"'"'- [ ] No secrets committed'"'"',
                '"'"'- [ ] CODEOWNERS are automatically notified'"'"',
                `- [ ] Risk tier \`${riskTier}\` — all compliance checks must pass`,
                `- [ ] If a check fails with no fix, raise a waiver at https://github.com/${govOrg}/${govRepo}/issues/new?template=waiver-request.yml`
              ].join('"'"'\n'"'"');
              await upsertFile(repoName, '"'"'.github/PULL_REQUEST_TEMPLATE.md'"'"', prTemplate, '"'"'chore: add PR template [repo-factory]'"'"');

              // ── 7. Risk tier label ──────────────────────────────────────────
              const colours = { standard: '"'"'0075ca'"'"', elevated: '"'"'e4a11b'"'"', critical: '"'"'cf222e'"'"' };
              await engApi('"'"'POST'"'"', `/repos/${engOrg}/${repoName}/labels`, {
                name: `risk:${riskTier}`, color: colours[riskTier] || '"'"'6e7781'"'"', description: `Risk tier: ${riskTier}`
              });

              // ── 8. Close issue with success ─────────────────────────────────
              const repoUrl = `https://github.com/${engOrg}/${repoName}`;
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: [
                  '"'"'## ✅ Repository Provisioned'"'"',
                  '"'"''"'"',
                  `🎉 @${issueAuthor} — your repository is ready!`,
                  '"'"''"'"',
                  `**→ [${engOrg}/${repoName}](${repoUrl})**`,
                  '"'"''"'"',
                  '"'"'**What was created:**'"'"',
                  `- ✅ Repository · visibility: \`${visibility}\` · risk: \`${riskTier}\``,
                  `- ✅ Teams: ${teamAccess.map(t => `\`${t.team}\` (${t.permission})`).join('"'"', '"'"')}`,
                  '"'"'- ✅ `.github/CODEOWNERS`'"'"',
                  '"'"'- ✅ `.github/workflows/compliance.yml`'"'"',
                  '"'"'- ✅ `.github/PULL_REQUEST_TEMPLATE.md`'"'"',
                  '"'"''"'"',
                  '"'"'**Next steps:**'"'"',
                  `1. Clone: \`git clone https://github.com/${engOrg}/${repoName}.git\``,
                  '"'"'2. All PRs will run compliance checks automatically'"'"',
                  `3. Failing checks require a waiver → https://github.com/${govOrg}/${govRepo}/issues/new?template=waiver-request.yml`
                ].join('"'"'\n'"'"')
              });

              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'repo-provisioned'"'"'] });
              await github.rest.issues.update({
                ...context.repo, issue_number: issueNumber, state: '"'"'closed'"'"', state_reason: '"'"'completed'"'"'
              });

            } catch (err) {
              core.error(`Provisioning failed: ${err.message}`);
              await github.rest.issues.createComment({
                ...context.repo, issue_number: issueNumber,
                body: `## ❌ Provisioning Failed\n\n\`\`\`\n${err.message}\n\`\`\`\n\nPing @${govOrg}/platform-admins for manual intervention.`
              });
              await github.rest.issues.addLabels({ ...context.repo, issue_number: issueNumber, labels: ['"'"'provisioning-failed'"'"'] });
              core.setFailed(err.message);
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/repo-provision.yml" \
  "$REPO_PROVISION_WF" \
  "chore: add repo-provision workflow [governance-setup]"

success "All repo request issue workflows pushed"
info "Engineers can now open an issue at: https://github.com/$PLATFORM_ORG/$GOVERNANCE_REPO/issues/new?template=repo-request.yml"
