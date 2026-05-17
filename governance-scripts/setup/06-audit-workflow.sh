#!/usr/bin/env bash
# setup/06-audit-workflow.sh — Push the central audit report workflow

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

step "Pushing central-audit-report.yml"

AUDIT_WORKFLOW="name: \"Central Compliance Audit Report\"
on:
  schedule:
    - cron: \"0 7 * * 1\"   # Every Monday 07:00 UTC
  workflow_dispatch:

jobs:
  generate-report:
    runs-on: ubuntu-latest
    permissions:
      issues: write
      contents: read
    steps:
      - name: Generate central audit report
        uses: actions/github-script@v7
        env:
          AUDIT_TOKEN: \${{ secrets.AUDIT_REPORT_TOKEN }}
          ORG_NAME: ${GITHUB_ORG}
        with:
          github-token: \${{ secrets.GITHUB_TOKEN }}
          script: |
            const today = new Date().toISOString().split('T')[0];
            const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
            const token = process.env.AUDIT_TOKEN;
            const org = process.env.ORG_NAME;

            async function callAPI(path) {
              if (!token) return [];
              const res = await fetch(\`https://api.github.com\${path}\`, {
                headers: { Authorization: \`Bearer \${token}\`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' }
              });
              return res.ok ? res.json() : [];
            }

            // 1. Current org admins
            const admins = await callAPI(\`/orgs/\${org}/members?role=admin&per_page=100\`);
            const adminList = Array.isArray(admins) && admins.length > 0
              ? admins.map(m => \`- @\${m.login}\`).join('\n')
              : '_Unable to fetch (check AUDIT_REPORT_TOKEN scope) — query manually: gh api /orgs/{org}/members?role=admin_';

            // 2. Open approved waivers
            const openWaivers = await github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: 'waiver-approved', state: 'open', per_page: 50 });
            const waiverRows = openWaivers.data.length === 0
              ? '| — | No open approved waivers | — |'
              : openWaivers.data.map(i => { const exp = (i.title.match(/\[EXPIRES:(.+?)\]/) || [])[1] || 'unknown'; return \`| [#\${i.number}](\${i.html_url}) | \${i.title.replace(/\\s*\\[EXPIRES.*/, '')} | \${exp} |\`; }).join('\n');

            // 3. Expired this week
            const expired = await github.rest.issues.listForRepo({ owner: context.repo.owner, repo: context.repo.repo, labels: 'waiver-expired', state: 'closed', since: oneWeekAgo, per_page: 50 });

            // 4. Ruleset bypasses (enterprise audit log)
            let bypassSection = '> Requires read:audit_log on AUDIT_REPORT_TOKEN.\n> Manual query: gh api \"/enterprises/{enterprise}/audit-log?phrase=action:protected_branch.policy_override\"';
            try {
              const bypasses = await callAPI(\`/enterprises/${GITHUB_ENTERPRISE:-my-enterprise}/audit-log?phrase=action:protected_branch.policy_override&per_page=30\`);
              if (Array.isArray(bypasses) && bypasses.length > 0) {
                const recent = bypasses.filter(e => new Date(e.created_at) > new Date(oneWeekAgo));
                bypassSection = recent.length === 0 ? '✅ No ruleset bypasses in the last 7 days.' : recent.map(e => \`- **\${e.actor}** bypassed controls on \\\`\${e.repo}\\\` — \${e.created_at}\`).join('\n');
              }
            } catch (_) {}

            // 5. New repos this week
            let newReposSection = '> Requires read:audit_log. Manual: gh api \"/enterprises/{enterprise}/audit-log?phrase=action:repo.create\"';
            try {
              const repos = await callAPI(\`/enterprises/${GITHUB_ENTERPRISE:-my-enterprise}/audit-log?phrase=action:repo.create&per_page=30\`);
              if (Array.isArray(repos)) {
                const recent = repos.filter(e => new Date(e.created_at) > new Date(oneWeekAgo));
                newReposSection = recent.length === 0 ? '✅ No new repositories this week.' : recent.map(e => \`- \\\`\${e.repo}\\\` created by **\${e.actor}** — \${e.created_at}\`).join('\n');
              }
            } catch (_) {}

            const dismissedNote = \`
\\\`\\\`\\\`bash
# Secret scanning dismissals per repo
gh api \"/repos/{owner}/{repo}/secret-scanning/alerts?state=resolved&per_page=100\" \\\\
  --jq '.[] | {number, secret_type, resolved_by: .resolved_by.login, reason: .resolution, at: .resolved_at}'

# Code scanning dismissals per repo
gh api \"/repos/{owner}/{repo}/code-scanning/alerts?state=dismissed&per_page=100\" \\\\
  --jq '.[] | {number, rule: .rule.id, dismissed_by: .dismissed_by.login, reason: .dismissed_reason}'
\\\`\\\`\\\`\`;

            const prNote = \`
\\\`\\\`\\\`bash
# Reviews on a specific PR
gh api \"/repos/{owner}/{repo}/pulls/{pr}/reviews\" \\\\
  --jq '.[] | {reviewer: .user.login, state, submitted_at}'

# Merged PRs on main
gh api \"/repos/{owner}/{repo}/pulls?state=closed&base=main&per_page=100\" \\\\
  --jq '.[] | select(.merged_at != null) | {number, merged_by: .merged_by.login, merged_at}'
\\\`\\\`\\\`\`;

            const body = \`## 📋 Central Compliance Audit Report — Week of \${today}

---

### 1. 🔑 Current Organisation Administrators (\${org})

\${adminList}

---

### 2. ⚠️ Open Approved Waivers

| Issue | Description | Expires |
|---|---|---|
\${waiverRows}

---

### 3. Waivers Expired This Week: \${expired.data.length}

---

### 4. 🚨 Branch Ruleset Bypasses (Last 7 Days)

\${bypassSection}

---

### 5. 📦 New Repositories Created This Week

\${newReposSection}

---

### 6. 🔍 Dismissed Security Alerts (Pull on Demand)

\${dismissedNote}

---

### 7. PR Approvals & CODEOWNERS Sign-Off (Pull on Demand)

\${prNote}

---

_Report covers 7 days ending \${today}. Maintained by Platform Governance team._\`;

            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: \`[AUDIT REPORT] Central Compliance Report — \${today}\`,
              body: body.trim(), labels: ['audit-report']
            });"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/central-audit-report.yml" "$AUDIT_WORKFLOW" \
  "chore: add central-audit-report workflow [governance-setup]"

success "Audit report workflow pushed"
