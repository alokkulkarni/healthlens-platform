#!/usr/bin/env bash
# setup/04-compliance-workflow.sh — Push compliance.yml template and governance CODEOWNERS
# compliance.yml is pushed to .github/templates/ (repo factory copies it to new repos)

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

GOV_FULL="$PLATFORM_ORG/$GOVERNANCE_REPO"

step "Pushing compliance.yml template to governance repo"
info "This file is copied to every new repo by the repo factory."
info "Update it here and run sync-compliance.sh to push to existing repos."

# The WAIVER_BYPASS_SCRIPT is a shared JS snippet used by all scanner jobs.
# Each job calls it with a different checkName to look up a per-check waiver.
COMPLIANCE_YML='name: "Compliance — Security, Quality & Testing Gates"
on:
  pull_request:
    branches: [main, master, release]

# Shared waiver bypass script — injected into each job
env:
  WAIVER_BYPASS_SCRIPT: |
    const token = process.env.GOVERNANCE_READ_TOKEN;
    const prNumber = context.payload.pull_request?.number;
    const callingRepo = context.repo.owner + "/" + context.repo.repo;
    const govRepo = process.env.GOVERNANCE_REPO;
    const [govOwner, govRepoName] = govRepo.split("/");
    const checkName = process.env.CHECK_NAME;

    const res = await fetch(
      `https://api.github.com/repos/${govOwner}/${govRepoName}/issues?labels=waiver-approved&state=open&per_page=100`,
      { headers: { Authorization: `token ${token}`, Accept: "application/vnd.github+json" } }
    );
    const issues = await res.json();
    const today = new Date();

    for (const issue of issues) {
      const b = (issue.body || "").toLowerCase();
      if (!b.includes(callingRepo.toLowerCase())) continue;
      if (!b.includes(`#${prNumber}`)) continue;
      if (checkName && !b.includes(checkName.toLowerCase())) continue;
      const m = issue.title.match(/\[EXPIRES:(\d{4}-\d{2}-\d{2})\]/);
      if (!m || new Date(m[1]) < today) continue;
      core.warning(`Waiver active for ${checkName}: ${issue.html_url} (expires ${m[1]})`);
      return;
    }
    core.setFailed(`No approved waiver found for check "${checkName}" on ${callingRepo} PR #${prNumber}. Fix the issue or raise a waiver in the governance repository.`);

jobs:
  # ── GitHub Advanced Security (CodeQL) ────────────────────────────────────────
  codeql:
    name: "CodeQL / Analyze"
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      actions: read
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ github.event.repository.default_branch && '"'"'javascript,python'"'"' || '"'"'javascript'"'"' }}
      - uses: github/codeql-action/autobuild@v3
      - id: codeql_scan
        uses: github/codeql-action/analyze@v3
        continue-on-error: true
      - name: Check waiver if CodeQL failed
        if: steps.codeql_scan.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "CodeQL / Analyze"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── SonarQube ────────────────────────────────────────────────────────────────
  sonarqube:
    name: "SonarQube Analysis"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: sonar_scan
        uses: sonarsource/sonarqube-scan-action@v3
        continue-on-error: true
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
      - name: Check waiver if SonarQube failed
        if: steps.sonar_scan.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "SonarQube Analysis"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── Nexus IQ ─────────────────────────────────────────────────────────────────
  nexus-iq:
    name: "Nexus IQ Policy Evaluation"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: nexus_scan
        uses: sonatype-nexus-community/iq-github-action@main
        continue-on-error: true
        with:
          serverUrl: ${{ secrets.NEXUS_IQ_URL }}
          username: ${{ secrets.NEXUS_IQ_USERNAME }}
          password: ${{ secrets.NEXUS_IQ_PASSWORD }}
          applicationId: ${{ github.event.repository.name }}
          stage: build
      - name: Check waiver if Nexus IQ failed
        if: steps.nexus_scan.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "Nexus IQ Policy Evaluation"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── Unit Tests & Coverage ─────────────────────────────────────────────────────
  unit-tests:
    name: "Unit Tests & Coverage"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: unit_test
        run: |
          # Adjust this command for your language / build tool:
          # npm test -- --coverage   (Node.js)
          # ./gradlew test jacocoTestReport  (Java/Gradle)
          # pytest --cov=src --cov-report=xml  (Python)
          echo "Replace this with your test command"
          exit 0
        continue-on-error: true
      - uses: dorny/test-reporter@v1
        if: always()
        with:
          name: Unit Test Results
          path: test-results/junit.xml
          reporter: java-junit
          fail-on-error: false
      - name: Check waiver if tests failed
        if: steps.unit_test.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "Unit Tests & Coverage"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── Integration Tests ─────────────────────────────────────────────────────────
  integration-tests:
    name: "Integration Tests"
    runs-on: ubuntu-latest
    needs: [unit-tests]
    steps:
      - uses: actions/checkout@v4
      - id: integration_test
        run: |
          echo "Replace this with your integration test command"
          exit 0
        continue-on-error: true
      - name: Check waiver if integration tests failed
        if: steps.integration_test.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "Integration Tests"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── DAST / ZAP (release PRs only) ────────────────────────────────────────────
  dast-scan:
    name: "DAST Security Scan (ZAP)"
    runs-on: ubuntu-latest
    if: github.base_ref == '"'"'main'"'"' || github.base_ref == '"'"'release'"'"'
    steps:
      - uses: actions/checkout@v4
      - id: zap_scan
        uses: zaproxy/action-full-scan@v0.10.0
        continue-on-error: true
        with:
          target: ${{ secrets.STAGING_APP_URL }}
          rules_file_name: .github/zap-rules.tsv
          fail_action: true
      - name: Check waiver if DAST failed
        if: steps.zap_scan.outcome == '"'"'failure'"'"'
        uses: actions/github-script@v7
        env:
          GOVERNANCE_READ_TOKEN: ${{ secrets.GOVERNANCE_READ_TOKEN }}
          GOVERNANCE_REPO: '"'"''"'"'
          CHECK_NAME: "DAST Security Scan / ZAP"
        with:
          script: eval(process.env.WAIVER_BYPASS_SCRIPT)

  # ── General waiver check ──────────────────────────────────────────────────────
  waiver-check:
    name: "waiver-check"
    uses: '"$PLATFORM_ORG/$GOVERNANCE_REPO"'/.github/workflows/waiver-check.yml@main
    secrets: inherit'

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/templates/compliance.yml" \
  "$COMPLIANCE_YML" \
  "chore: add canonical compliance workflow template [governance-setup]"

# ── CODEOWNERS for governance repo ────────────────────────────────────────────
step "Pushing CODEOWNERS to governance repository"

CODEOWNERS="# .github/CODEOWNERS — Governance Repository
# Platform admins must approve ALL changes in this repository.
# No engineer can self-approve a repo, team, or workflow change.

# Default — platform admins own everything
*                               @${PLATFORM_ORG}/platform-admins

# Repo definitions — all new repo requests require platform admin review
/repos/                         @${PLATFORM_ORG}/platform-admins

# Team definitions — all team changes require platform admin review
/teams/                         @${PLATFORM_ORG}/platform-admins

# Governance workflows — require two platform admins (ruleset enforces 2 reviews)
/.github/workflows/             @${PLATFORM_ORG}/platform-admins

# Waiver template — compliance team co-owns to catch scope changes
/.github/ISSUE_TEMPLATE/        @${PLATFORM_ORG}/platform-admins @${PLATFORM_ORG}/compliance-team

# Canonical compliance template
/.github/templates/             @${PLATFORM_ORG}/platform-admins"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/CODEOWNERS" \
  "$CODEOWNERS" \
  "chore: add CODEOWNERS for governance repo [governance-setup]"

# ── PR template for governance repo ───────────────────────────────────────────
step "Pushing PR template for governance repository"

PR_TEMPLATE="## What does this PR do?

<!-- Describe the change. Be concise. -->

## Checklist

- [ ] This is a new **repository definition** (repos/ folder) — all required fields filled in
- [ ] This is a new **team definition** (teams/ folder) — members verified against HR record
- [ ] This is a **workflow change** — tested in a fork before raising this PR
- [ ] CODEOWNERS verified for any new repos (platform-admins always own .github/**)
- [ ] Risk tier is correct for the repository being created"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/PULL_REQUEST_TEMPLATE.md" \
  "$PR_TEMPLATE" \
  "chore: add PR template for governance repo [governance-setup]"

success "Compliance workflow template and governance CODEOWNERS pushed"
info "GOVERNANCE_REPO placeholder in compliance.yml needs to be set at runtime."
info "The repo factory replaces the placeholder when copying to new repos."
