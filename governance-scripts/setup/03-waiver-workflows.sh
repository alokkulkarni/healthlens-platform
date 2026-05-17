#!/usr/bin/env bash
# setup/03-waiver-workflows.sh — Push all waiver system files
# Pushes: waiver-request issue template, waiver-process, waiver-check, waiver-expiry, waiver-report

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-org)    PLATFORM_ORG="$2";    shift 2 ;;
    --governance-repo) GOVERNANCE_REPO="$2"; shift 2 ;;
    --org)             GITHUB_ORG="$2";      shift 2 ;;
    *) shift ;;
  esac
done

load_config
: "${PLATFORM_ORG:?Set --platform-org}"
: "${GOVERNANCE_REPO:?Set --governance-repo}"
: "${GITHUB_ORG:=${PLATFORM_ORG}}"

# ── Waiver request issue template ─────────────────────────────────────────────
step "Pushing waiver request issue template"

WAIVER_FORM='name: "Compliance Waiver Request"
description: "Request a time-limited bypass for a failing compliance check when no immediate fix exists"
title: "[WAIVER] "
labels: ["waiver-pending"]
assignees: []
body:
  - type: markdown
    attributes:
      value: |
        ## Compliance Waiver Request
        Complete all fields. Incomplete requests will be rejected.
        The risk owner you name will receive a notification to approve or reject this waiver.

  - type: input
    id: repository
    attributes:
      label: "Repository"
      description: "Full repo name (e.g. my-org/payment-service)"
      placeholder: "my-org/repo-name"
    validations:
      required: true

  - type: input
    id: pr_number
    attributes:
      label: "Pull Request Number"
      description: "The PR number that is blocked (e.g. 42)"
      placeholder: "42"
    validations:
      required: true

  - type: dropdown
    id: failing_check
    attributes:
      label: "Failing Check"
      description: "Select the exact check that is failing and needs a waiver"
      options:
        - "CodeQL / Analyze (GHAS — code vulnerability)"
        - "Secret Scanning (GHAS — credential in code)"
        - "SonarQube Analysis (code quality / SAST)"
        - "Nexus IQ Policy Evaluation (CVE in third-party library)"
        - "Nexus IQ Policy Evaluation (licence violation)"
        - "Unit Tests & Coverage (test failure or coverage below threshold)"
        - "Integration Tests (integration test failure)"
        - "Contract Tests (Pact) (contract test failure)"
        - "DAST Security Scan / ZAP (dynamic security finding)"
    validations:
      required: true

  - type: textarea
    id: justification
    attributes:
      label: "Business Justification"
      description: "Why must this PR merge now without fixing the issue? Include evidence that no fix exists."
      placeholder: |
        - What is the finding (CVE ID, rule name, test name)?
        - Why can it not be fixed now?
        - What compensating controls are in place?
        - Link to library issue tracker / upstream ticket if applicable
    validations:
      required: true

  - type: input
    id: risk_owner
    attributes:
      label: "Risk Owner (GitHub username)"
      description: "The person accepting accountability. They will be notified to approve."
      placeholder: "@username"
    validations:
      required: true

  - type: input
    id: remediation_date
    attributes:
      label: "Remediation Date"
      description: "Date by which you commit to fixing the issue (max 30 days, format: YYYY-MM-DD)"
      placeholder: "2024-12-31"
    validations:
      required: true

  - type: checkboxes
    id: acknowledgement
    attributes:
      label: "Acknowledgements"
      options:
        - label: "I confirm no fix currently exists and I have documented why"
          required: true
        - label: "I accept that this waiver expires on the remediation date and the check will re-block merges"
          required: true
        - label: "I understand this waiver is recorded permanently in the compliance audit log"
          required: true'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/ISSUE_TEMPLATE/waiver-request.yml" \
  "$WAIVER_FORM" \
  "chore: add waiver request issue template [governance-setup]"

# ── waiver-process.yml ─────────────────────────────────────────────────────────
step "Pushing waiver-process.yml"

WAIVER_PROCESS='name: "Waiver Process"
on:
  issues:
    types: [opened, edited]
  issue_comment:
    types: [created]

jobs:
  handle-waiver:
    if: contains(github.event.issue.labels.*.name, '"'"'waiver-pending'"'"') || contains(github.event.issue.labels.*.name, '"'"'waiver-approved'"'"')
    runs-on: ubuntu-latest
    permissions:
      issues: write
      contents: read
    steps:
      - name: Process waiver submission or approval
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const issue = context.payload.issue;
            const comment = context.payload.comment;
            const commenter = comment?.user?.login || "";
            const body = issue?.body || "";

            // Extract fields from issue form
            const repoMatch    = body.match(/### Repository\s*\n\s*(.+)/);
            const prMatch      = body.match(/### Pull Request Number\s*\n\s*(\d+)/);
            const checkMatch   = body.match(/### Failing Check\s*\n\s*(.+)/);
            const ownerMatch   = body.match(/### Risk Owner[^\n]*\s*\n\s*@?(\S+)/);
            const dateMatch    = body.match(/### Remediation Date\s*\n\s*(\d{4}-\d{2}-\d{2})/);

            const repo          = repoMatch?.[1]?.trim();
            const prNumber      = prMatch?.[1]?.trim();
            const failingCheck  = checkMatch?.[1]?.trim();
            const riskOwner     = ownerMatch?.[1]?.trim();
            const remDate       = dateMatch?.[1]?.trim();

            // ── Validate remediation date (max 30 days) ──────────────────────
            if (context.payload.action === "opened" || context.payload.action === "edited") {
              if (!repo || !prNumber || !failingCheck || !riskOwner || !remDate) {
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: "⚠️ **Incomplete waiver request.** Please ensure all fields are filled in and re-submit."
                });
                return;
              }

              const remDateObj = new Date(remDate);
              const maxDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
              if (remDateObj > maxDate) {
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: `⚠️ **Remediation date too far.** Maximum waiver period is 30 days. Please set a date on or before ${maxDate.toISOString().split("T")[0]}.`
                });
                return;
              }

              // Update title to include expiry marker
              const currentTitle = issue.title;
              if (!currentTitle.includes("[EXPIRES:")) {
                await github.rest.issues.update({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  title: `${currentTitle} [EXPIRES:${remDate}]`
                });
              }

              // Notify risk owner
              await github.rest.issues.createComment({
                owner: context.repo.owner, repo: context.repo.repo,
                issue_number: issue.number,
                body: `📋 **Waiver request received.**\n\n@${riskOwner} — you are listed as the risk owner for this waiver. Please review and respond with:\n- \`/approve-waiver\` to approve\n- \`/reject-waiver <reason>\` to reject\n\nThis waiver covers **${failingCheck}** on PR #${prNumber} in \`${repo}\`. It expires **${remDate}**.`
              });
            }

            // ── Handle approval / rejection commands ─────────────────────────
            if (context.payload.action === "created" && comment) {
              const commentBody = comment.body?.trim() || "";

              if (commentBody.startsWith("/approve-waiver")) {
                await github.rest.issues.removeLabel({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, name: "waiver-pending"
                }).catch(() => {});
                await github.rest.issues.addLabels({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, labels: ["waiver-approved"]
                });
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: `✅ **Waiver Approved** by @${commenter} on ${new Date().toISOString().split("T")[0]}.\n\nThe compliance check will now pass for the referenced PR. This waiver is recorded permanently in the audit log.\n\n⚠️ This waiver expires on the remediation date. The check will re-block merges after expiry.`
                });
              }

              if (commentBody.startsWith("/reject-waiver")) {
                const reason = commentBody.replace("/reject-waiver", "").trim() || "No reason given";
                await github.rest.issues.removeLabel({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, name: "waiver-pending"
                }).catch(() => {});
                await github.rest.issues.addLabels({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, labels: ["waiver-rejected"]
                });
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: `❌ **Waiver Rejected** by @${commenter}.\n\n**Reason:** ${reason}\n\nThe PR remains blocked. The engineer must fix the failing check or escalate for further review.`
                });
                await github.rest.issues.update({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, state: "closed"
                });
              }
            }'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/waiver-process.yml" \
  "$WAIVER_PROCESS" \
  "chore: add waiver-process workflow [governance-setup]"

# ── waiver-check.yml ───────────────────────────────────────────────────────────
step "Pushing waiver-check.yml"

WAIVER_CHECK='name: "Waiver Check"
on:
  workflow_call:
    inputs:
      pr_number:
        description: "PR number to check"
        required: false
        type: string
      check_name:
        description: "Specific check name to look for a waiver (empty = general PR waiver)"
        required: false
        type: string
        default: ""
    outputs:
      waiver_found:
        description: "Whether a valid waiver was found"
        value: ${{ jobs.check.outputs.waiver_found }}
      waiver_url:
        description: "URL of the approved waiver issue"
        value: ${{ jobs.check.outputs.waiver_url }}
      waiver_expiry:
        description: "Expiry date of the waiver"
        value: ${{ jobs.check.outputs.waiver_expiry }}
  pull_request:
    branches: [main, master, release, develop]

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      statuses: write
      contents: read
    outputs:
      waiver_found: ${{ steps.lookup.outputs.waiver_found }}
      waiver_url: ${{ steps.lookup.outputs.waiver_url }}
      waiver_expiry: ${{ steps.lookup.outputs.waiver_expiry }}
    steps:
      - name: Look up waiver
        id: lookup
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          CHECK_NAME: ${{ inputs.check_name || '"'"''"'"' }}
          PR_NUMBER: ${{ inputs.pr_number || github.event.pull_request.number }}
          CALLING_REPO: ${{ github.repository }}
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const token     = process.env.GOVERNANCE_READ_TOKEN;
            const checkName = process.env.CHECK_NAME;
            const prNumber  = process.env.PR_NUMBER;
            const callingRepo = process.env.CALLING_REPO;
            const govRepo   = process.env.GOVERNANCE_REPO || "'"$PLATFORM_ORG/$GOVERNANCE_REPO"'";
            const [govOwner, govRepoName] = govRepo.split("/");

            const govOctokit = github.rest;
            const headers = token
              ? { authorization: `token ${token}` }
              : {};

            const issues = await govOctokit.issues.listForRepo({
              owner: govOwner, repo: govRepoName,
              labels: "waiver-approved", state: "open", per_page: 100,
              headers
            });

            const today = new Date();

            for (const issue of issues.data) {
              const bodyLower = (issue.body || "").toLowerCase();
              const repoInBody = bodyLower.includes(callingRepo.toLowerCase());
              const prInBody   = bodyLower.includes(`#${prNumber}`) || bodyLower.includes(`pr ${prNumber}`);

              if (!repoInBody || !prInBody) continue;

              // Check expiry
              const expiryMatch = issue.title.match(/\[EXPIRES:(\d{4}-\d{2}-\d{2})\]/);
              if (!expiryMatch) continue;
              const expiry = new Date(expiryMatch[1]);
              if (expiry < today) continue;

              // Check specific check name if requested
              if (checkName && !bodyLower.includes(checkName.toLowerCase())) continue;

              core.setOutput("waiver_found", "true");
              core.setOutput("waiver_url", issue.html_url);
              core.setOutput("waiver_expiry", expiryMatch[1]);
              core.warning(`⚠️ Waiver active: ${issue.html_url} — expires ${expiryMatch[1]}`);
              return;
            }

            core.setOutput("waiver_found", "false");
            core.setOutput("waiver_url", "");
            core.setOutput("waiver_expiry", "");

            if (!checkName) {
              // General PR waiver check — hard fail if none found
              core.setFailed(`No approved waiver found for ${callingRepo} PR #${prNumber}. If a compliance check has failed, raise a waiver in the governance repository.`);
            }'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/waiver-check.yml" \
  "$WAIVER_CHECK" \
  "chore: add waiver-check workflow [governance-setup]"

# ── waiver-expiry.yml ──────────────────────────────────────────────────────────
step "Pushing waiver-expiry.yml"

WAIVER_EXPIRY='name: "Waiver Expiry"
on:
  schedule:
    - cron: "0 6 * * *"   # Daily at 06:00 UTC
  workflow_dispatch:

jobs:
  check-expiry:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - name: Check and close expired waivers
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const today = new Date();
            const warnDate = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner, repo: context.repo.repo,
              labels: "waiver-approved", state: "open", per_page: 100
            });

            for (const issue of issues.data) {
              const match = issue.title.match(/\[EXPIRES:(\d{4}-\d{2}-\d{2})\]/);
              if (!match) continue;
              const expiry = new Date(match[1]);

              if (expiry < today) {
                // Expired — close and relabel
                await github.rest.issues.removeLabel({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, name: "waiver-approved"
                }).catch(() => {});
                await github.rest.issues.addLabels({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, labels: ["waiver-expired"]
                });
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: "⏰ **Waiver expired.** The remediation date has passed. The compliance check will now block PRs again. Please fix the underlying issue or raise a new waiver with updated justification."
                });
                await github.rest.issues.update({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, state: "closed"
                });
                core.info(`Closed expired waiver #${issue.number}`);

              } else if (expiry < warnDate && !issue.labels.find(l => l.name === "expiry-warning-sent")) {
                // 7-day warning
                const daysLeft = Math.ceil((expiry - today) / (24 * 60 * 60 * 1000));
                await github.rest.issues.createComment({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number,
                  body: `⚠️ **Waiver expiring in ${daysLeft} day(s).** Please remediate the underlying issue or raise a renewal request before **${match[1]}**.`
                });
                await github.rest.issues.addLabels({
                  owner: context.repo.owner, repo: context.repo.repo,
                  issue_number: issue.number, labels: ["expiry-warning-sent"]
                });
              }
            }'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/waiver-expiry.yml" \
  "$WAIVER_EXPIRY" \
  "chore: add waiver-expiry workflow [governance-setup]"

# ── waiver-report.yml ──────────────────────────────────────────────────────────
step "Pushing waiver-report.yml"

WAIVER_REPORT='name: "Weekly Compliance Report"
on:
  schedule:
    - cron: "0 7 * * 1"   # Every Monday at 07:00 UTC
  workflow_dispatch:

jobs:
  generate-report:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - name: Generate weekly compliance report
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const today = new Date().toISOString().split("T")[0];
            const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

            const [pending, approved, expired, rejected] = await Promise.all([
              github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: "waiver-pending", state: "open", per_page: 100 }),
              github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: "waiver-approved", state: "open", per_page: 100 }),
              github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: "waiver-expired", state: "closed", since: oneWeekAgo, per_page: 50 }),
              github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: "waiver-rejected", state: "closed", since: oneWeekAgo, per_page: 50 }),
            ]);

            const rows = (issues) => issues.data.length === 0
              ? "| — | No entries | — |"
              : issues.data.map(i => {
                  const expiry = (i.title.match(/\[EXPIRES:(.+?)\]/) || [])[1] || "—";
                  return `| [#${i.number}](${i.html_url}) | ${i.title.replace(/\s*\[EXPIRES.*/, "")} | ${expiry} |`;
                }).join("\n");

            const body = `## Weekly Compliance Report — ${today}\n\n` +
              `| | Count |\n|---|---|\n` +
              `| Pending approval | ${pending.data.length} |\n` +
              `| Approved (active) | ${approved.data.length} |\n` +
              `| Expired this week | ${expired.data.length} |\n` +
              `| Rejected this week | ${rejected.data.length} |\n\n` +
              `### Open Approved Waivers\n| Issue | Description | Expires |\n|---|---|---|\n${rows(approved)}\n\n` +
              `### Pending Approval\n| Issue | Description | Expires |\n|---|---|---|\n${rows(pending)}\n\n` +
              `_Auto-generated every Monday. All waiver issues are the permanent compliance audit trail._`;

            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: `[COMPLIANCE REPORT] Week of ${today}`,
              body, labels: ["compliance-report"]
            });'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/waiver-report.yml" \
  "$WAIVER_REPORT" \
  "chore: add waiver-report workflow [governance-setup]"

success "All waiver system files pushed"
