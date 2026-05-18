#!/usr/bin/env bash
# setup/05c-coverage-workflow.sh — Reusable test coverage governance workflow
# Pushes .github/workflows/coverage-report.yml to the governance repo.
# Engineering repos call this via `uses:` after their unit-test job; it:
#   • Posts a coverage summary comment on the PR
#   • Creates/updates a per-repo coverage tracking issue in governance
#   • Fails the check (blocks merge) if coverage < threshold — requires waiver

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

step "Pushing coverage-report.yml (reusable workflow) to $PLATFORM_ORG/$GOVERNANCE_REPO"

COVERAGE_REPORT_WF='name: "Coverage Report (Reusable)"

on:
  workflow_call:
    inputs:
      coverage_pct:
        description: "Coverage percentage as a string (0–100). Set from your test runner output."
        required: false
        type: string
        default: "0"
      tests_passed:
        description: "Number of passing tests."
        required: false
        type: string
        default: "0"
      tests_failed:
        description: "Number of failing tests."
        required: false
        type: string
        default: "0"
      tests_skipped:
        description: "Number of skipped tests."
        required: false
        type: string
        default: "0"
      threshold:
        description: "Minimum coverage % required (default 80). Override per-repo via env var."
        required: false
        type: string
        default: "80"
      report_url:
        description: "Optional URL to the full coverage HTML report."
        required: false
        type: string
        default: ""
    secrets:
      GOVERNANCE_APP_ID:
        required: true
      GOVERNANCE_APP_PRIVATE_KEY:
        required: true

jobs:
  coverage-gate:
    name: "Coverage Check"
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
      pull-requests: write

    steps:
      - name: Generate governance token
        id: gov-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.GOVERNANCE_APP_ID }}
          private-key: ${{ secrets.GOVERNANCE_APP_PRIVATE_KEY }}
          owner: '"$PLATFORM_ORG"'

      - name: Evaluate coverage and log to governance
        id: evaluate
        uses: actions/github-script@v7
        env:
          GOV_TOKEN:      ${{ steps.gov-token.outputs.token }}
          GOVERNANCE_ORG:  '"$PLATFORM_ORG"'
          GOVERNANCE_REPO: '"$GOVERNANCE_REPO"'
          COVERAGE_PCT:   ${{ inputs.coverage_pct }}
          THRESHOLD:      ${{ inputs.threshold }}
          TESTS_PASSED:   ${{ inputs.tests_passed }}
          TESTS_FAILED:   ${{ inputs.tests_failed }}
          TESTS_SKIPPED:  ${{ inputs.tests_skipped }}
          REPORT_URL:     ${{ inputs.report_url }}
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const pct       = parseFloat(process.env.COVERAGE_PCT) || 0;
            const threshold = parseFloat(process.env.THRESHOLD) || 80;
            const passed    = parseInt(process.env.TESTS_PASSED)  || 0;
            const failed    = parseInt(process.env.TESTS_FAILED)  || 0;
            const skipped   = parseInt(process.env.TESTS_SKIPPED) || 0;
            const reportUrl = process.env.REPORT_URL || '"''"';
            const govOrg    = process.env.GOVERNANCE_ORG;
            const govRepo   = process.env.GOVERNANCE_REPO;
            const govToken  = process.env.GOV_TOKEN;

            const callingOwner = context.repo.owner;
            const callingRepo  = context.repo.repo;
            const passed_gate  = pct >= threshold;
            const pctStr       = pct.toFixed(1);
            const emoji        = passed_gate ? '"'"'✅'"'"' : '"'"'❌'"'"';
            const statusWord   = passed_gate ? '"'"'PASS'"'"' : '"'"'FAIL'"'"';
            const diff         = (threshold - pct).toFixed(1);
            const waiverUrl    = `https://github.com/${govOrg}/${govRepo}/issues/new?template=waiver-request.yml`;
            const total        = passed + failed + skipped;

            core.info(`Coverage: ${pctStr}% | Threshold: ${threshold}% | Status: ${statusWord}`);

            // ── Post or update PR comment ─────────────────────────────────────
            const prNumber = context.payload.pull_request?.number
              || context.payload.workflow_run?.pull_requests?.[0]?.number;

            if (prNumber) {
              const coverageColor = passed_gate ? '"'"'brightgreen'"'"' : '"'"'red'"'"';
              const badgePct      = encodeURIComponent(`${pctStr}%`);
              const badge         = `![coverage](https://img.shields.io/badge/coverage-${badgePct}-${coverageColor})`;

              const rows = [
                `| Metric | Value |`,
                `|--------|-------|`,
                `| ${emoji} Coverage | **${pctStr}%** _(threshold: ${threshold}%)_ |`,
                `| Tests passed | ${passed} |`,
                `| Tests failed | ${failed} |`,
                `| Tests skipped | ${skipped} |`,
                `| Total tests | ${total} |`,
                reportUrl ? `| Full report | [📊 View](${reportUrl}) |` : '"''"'
              ].filter(Boolean).join('"'"'\n'"'"');

              const verdict = passed_gate
                ? `✅ Coverage meets the **${threshold}%** minimum threshold.`
                : `❌ Coverage is **${diff}%** below the required **${threshold}%** threshold.\nFix failing tests, or raise a [compliance waiver](${waiverUrl}) if remediation cannot happen immediately.`;

              const comment = `## ${emoji} Coverage Report — ${statusWord}\n\n${badge}\n\n${rows}\n\n${verdict}`;

              const allComments = await github.rest.issues.listComments({
                owner: callingOwner, repo: callingRepo, issue_number: prNumber, per_page: 100
              });
              const existing = allComments.data.find(c =>
                c.user?.type === '"'"'Bot'"'"' && c.body?.includes('"'"'Coverage Report'"'"')
              );
              if (existing) {
                await github.rest.issues.updateComment({
                  owner: callingOwner, repo: callingRepo, comment_id: existing.id, body: comment
                });
              } else {
                await github.rest.issues.createComment({
                  owner: callingOwner, repo: callingRepo, issue_number: prNumber, body: comment
                });
              }

              // Add PR label
              const labelToAdd    = passed_gate ? '"'"'coverage:pass'"'"' : '"'"'coverage:below-threshold'"'"';
              const labelToRemove = passed_gate ? '"'"'coverage:below-threshold'"'"' : '"'"'coverage:pass'"'"';
              await github.rest.issues.addLabels({
                owner: callingOwner, repo: callingRepo, issue_number: prNumber, labels: [labelToAdd]
              }).catch(() => {});
              await github.rest.issues.removeLabel({
                owner: callingOwner, repo: callingRepo, issue_number: prNumber, name: labelToRemove
              }).catch(() => {});
            }

            // ── Update governance tracking issue ──────────────────────────────
            const govKit = {
              headers: {
                Authorization:        `Bearer ${govToken}`,
                Accept:               '"'"'application/vnd.github+json'"'"',
                '"'"'X-GitHub-Api-Version'"'"': '"'"'2022-11-28'"'"',
                '"'"'Content-Type'"'"':           '"'"'application/json'"'"'
              }
            };

            const trackTitle = `📊 Coverage Tracking: ${callingOwner}/${callingRepo}`;
            const now        = new Date().toISOString();
            const shortNow   = now.substring(0, 19).replace('"'"'T'"'"', '"'"' '"'"');
            const branch     = context.ref?.replace('"'"'refs/heads/'"'"', '"'"''"'"') || '"'"'unknown'"'"';
            const runUrl     = `https://github.com/${callingOwner}/${callingRepo}/actions/runs/${context.runId}`;
            const entryLine  = `| ${shortNow} | ${branch} | ${pctStr}% | ${passed} | ${failed} | ${skipped} | ${emoji} ${statusWord} | [Run](${runUrl}) |`;

            const searchUrl  = `https://api.github.com/search/issues?q=${encodeURIComponent(
              `repo:${govOrg}/${govRepo} is:issue label:coverage-report in:title "${callingOwner}/${callingRepo}"`
            )}&per_page=1`;
            const searchRes  = await fetch(searchUrl, govKit);
            const searchData = await searchRes.json();

            if (searchData.total_count > 0) {
              const issueNum    = searchData.items[0].number;
              const existBody   = searchData.items[0].body || '"''"';
              const headerLines = `# Coverage Tracking: \`${callingOwner}/${callingRepo}\`\n\n**Threshold:** ${threshold}% | **Latest:** ${pctStr}% (${emoji} ${statusWord})`;
              let newBody;
              if (existBody.includes('"'"'|-----------|'"'"')) {
                newBody = existBody
                  .replace(/(\*\*Threshold:.*\*\*Latest:.*\n)/, `**Threshold:** ${threshold}% | **Latest:** ${pctStr}% (${emoji} ${statusWord})\n`)
                  .replace(/(## History[\s\S]*?\|---+\|---+.*\|)\n/, `$1\n${entryLine}\n`);
              } else {
                newBody = existBody + '"'"'\n'"'"' + entryLine;
              }
              await fetch(`https://api.github.com/repos/${govOrg}/${govRepo}/issues/${issueNum}`, {
                method: '"'"'PATCH'"'"', ...govKit,
                body: JSON.stringify({ body: newBody })
              });
              core.info(`Updated governance tracking issue #${issueNum}`);
            } else {
              const tableHeader = [
                '"'"'## History'"'"', '"'"''"'"',
                '"'"'| Timestamp | Branch | Coverage | Passed | Failed | Skipped | Status | Run |'"'"',
                '"'"'|-----------|--------|----------|--------|--------|---------|--------|-----|'"'"',
                entryLine
              ].join('"'"'\n'"'"');
              const newIssueBody = `# Coverage Tracking: \`${callingOwner}/${callingRepo}\`\n\n**Threshold:** ${threshold}% | **Latest:** ${pctStr}% (${emoji} ${statusWord})\n\nThis issue is auto-maintained by the coverage gate workflow. Do not edit manually.\n\n${tableHeader}`;
              const createRes = await fetch(`https://api.github.com/repos/${govOrg}/${govRepo}/issues`, {
                method: '"'"'POST'"'"', ...govKit,
                body: JSON.stringify({ title: trackTitle, body: newIssueBody, labels: ['"'"'coverage-report'"'"'] })
              });
              const created = await createRes.json();
              core.info(`Created governance tracking issue #${created.number}`);
            }

            // ── Fail the gate if below threshold ──────────────────────────────
            if (!passed_gate) {
              core.setFailed(
                `Coverage ${pctStr}% is ${diff}% below the required ${threshold}% threshold. ` +
                `Fix failing tests or raise a waiver: ${waiverUrl}`
              );
            }
'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/coverage-report.yml" \
  "$COVERAGE_REPORT_WF" \
  "chore: add reusable coverage-report workflow [governance-setup]"

success "coverage-report.yml pushed"
info "Engineering repos call this via:  uses: $PLATFORM_ORG/$GOVERNANCE_REPO/.github/workflows/coverage-report.yml@main"
