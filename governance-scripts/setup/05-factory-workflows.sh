#!/usr/bin/env bash
# setup/05-factory-workflows.sh — Push repo-factory.yml, team-factory.yml and YAML templates

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

GOV="${PLATFORM_ORG}/${GOVERNANCE_REPO}"

# ── Repo YAML template ─────────────────────────────────────────────────────────
step "Pushing repos/_template.yml"

REPO_TEMPLATE="# repos/_template.yml
# ── How to use ───────────────────────────────────────────────────────────────
# 1. Copy this file: cp repos/_template.yml repos/{your-repo-name}.yml
# 2. Fill in ALL required fields (marked with ← REQUIRED)
# 3. Open a PR — platform admins are automatically added as required reviewers
# 4. On approval and merge, the repository is automatically created with:
#    - Team assignments, CODEOWNERS, compliance workflow, PR template, risk label

# ── Required fields ───────────────────────────────────────────────────────────
name: \"\"                          # ← REQUIRED: repo name (lowercase, hyphens, no spaces)
description: \"\"                   # ← REQUIRED: one-line description
visibility: private               # private | internal | public (public needs justification)

# ── Classification ────────────────────────────────────────────────────────────
risk_tier: standard               # standard | elevated | critical
business_domain: \"\"              # e.g. payments, identity, reporting, platform

# ── Topics ────────────────────────────────────────────────────────────────────
topics: []                        # e.g. [java, microservice, payments]

# ── Repo template (optional) ──────────────────────────────────────────────────
# Use a pre-approved starter template in platform-org. Leave blank for empty repo.
template: \"\"                     # e.g. java-springboot-template | nodejs-template

# ── Team access ────────────────────────────────────────────────────────────────
# Every repo must have at least one push team and platform-admins as admin.
# Create teams first in teams/ if they don't exist.
team_access:                      # ← REQUIRED: at least one entry
  - team: \"\"                     # ← REQUIRED: team slug (must exist in org)
    permission: push              # read | triage | push | maintain | admin
  - team: platform-admins
    permission: admin             # Do not remove — platform admins always need admin

# ── CODEOWNERS ─────────────────────────────────────────────────────────────────
# Who must review changes to different parts of this repo?
codeowners:                       # ← REQUIRED: at least the default pattern
  - pattern: \"**\"               # Default — all files
    owners:
      - \"\"                       # ← REQUIRED: replace with @your-org/your-team
  - pattern: \".github/**\"       # Governance files — always platform admins (do not remove)
    owners:
      - \"@${PLATFORM_ORG}/platform-admins\"

# ── Branch configuration ───────────────────────────────────────────────────────
default_branch: main

# ── Request metadata ──────────────────────────────────────────────────────────
requested_by: \"\"                 # ← REQUIRED: GitHub username
business_justification: \"\"      # ← REQUIRED: why does this repo need to exist?"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  "repos/_template.yml" "$REPO_TEMPLATE" \
  "chore: add repo definition template [governance-setup]"

# ── Team YAML template ─────────────────────────────────────────────────────────
step "Pushing teams/_template.yml"

TEAM_TEMPLATE="# teams/_template.yml
# ── How to use ───────────────────────────────────────────────────────────────
# 1. Copy this file: cp teams/_template.yml teams/{team-slug}.yml
# 2. Fill in all fields
# 3. Open a PR — on approval and merge, the team is created or updated

# ── Required fields ───────────────────────────────────────────────────────────
name: \"\"                          # ← REQUIRED: display name (e.g. \"Payments Backend\")
slug: \"\"                          # ← REQUIRED: URL-safe slug (e.g. payments-backend)
description: \"\"                   # ← REQUIRED: what does this team own?

# ── Visibility ─────────────────────────────────────────────────────────────────
privacy: closed                   # closed = visible to org members | secret = hidden

# ── Parent team (optional) ─────────────────────────────────────────────────────
parent_team: \"\"                   # Parent team slug, e.g. engineering (must exist first)

# ── Members ────────────────────────────────────────────────────────────────────
# All accounts must have active SSO-linked GitHub accounts.
maintainers:                      # ← At least one maintainer required
  - \"\"                           # GitHub username

members:
  - \"\"                           # GitHub username

# ── Request metadata ──────────────────────────────────────────────────────────
requested_by: \"\"
business_justification: \"\"      # e.g. new product team, domain expansion, etc."

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  "teams/_template.yml" "$TEAM_TEMPLATE" \
  "chore: add team definition template [governance-setup]"

# ── repo-factory.yml ───────────────────────────────────────────────────────────
step "Pushing repo-factory.yml"

REPO_FACTORY="name: \"Repo Factory — Provision New Repositories\"
on:
  push:
    branches: [main]
    paths:
      - \"repos/**.yml\"
  workflow_dispatch:
    inputs:
      repo_file:
        description: \"Specific repo YAML file to (re-)provision (e.g. repos/my-service.yml)\"
        required: false

jobs:
  provision:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changed repo definitions
        id: changed
        run: |
          if [ -n \"\${{ inputs.repo_file }}\" ]; then
            echo \"files=\${{ inputs.repo_file }}\" >> \"\$GITHUB_OUTPUT\"
          else
            CHANGED=\$(git diff --name-only HEAD~1 HEAD -- 'repos/*.yml' | grep -v '_template.yml' || true)
            echo \"files<<EOF\" >> \"\$GITHUB_OUTPUT\"
            echo \"\$CHANGED\" >> \"\$GITHUB_OUTPUT\"
            echo \"EOF\" >> \"\$GITHUB_OUTPUT\"
          fi

      - name: Provision repositories
        if: steps.changed.outputs.files != ''
        uses: actions/github-script@v7
        env:
          FACTORY_TOKEN: \${{ secrets.REPO_FACTORY_TOKEN }}
          CHANGED_FILES: \${{ steps.changed.outputs.files }}
          ORG_NAME: \${{ vars.GITHUB_ORG_NAME }}
          GOVERNANCE_REPO: ${PLATFORM_ORG}/${GOVERNANCE_REPO}
        with:
          github-token: \${{ secrets.GITHUB_TOKEN }}
          script: |
            const fs = require('fs');
            const yaml = require('js-yaml');
            const changedFiles = process.env.CHANGED_FILES.trim().split('\n').filter(Boolean);
            const org = process.env.ORG_NAME;
            const token = process.env.FACTORY_TOKEN;
            const govRepo = process.env.GOVERNANCE_REPO;

            async function api(method, endpoint, body = null) {
              const opts = { method, headers: { Authorization: \`Bearer \${token}\`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' } };
              if (body) opts.body = JSON.stringify(body);
              const res = await fetch(\`https://api.github.com\${endpoint}\`, opts);
              const text = await res.text();
              return { status: res.status, data: text ? JSON.parse(text) : {} };
            }

            async function upsertFile(repoName, filePath, content, msg) {
              const encoded = Buffer.from(content).toString('base64');
              const existing = await api('GET', \`/repos/\${org}/\${repoName}/contents/\${filePath}\`);
              const body = { message: msg, content: encoded, branch: 'main' };
              if (existing.status === 200) body.sha = existing.data.sha;
              await api('PUT', \`/repos/\${org}/\${repoName}/contents/\${filePath}\`, body);
            }

            const results = [];

            for (const file of changedFiles) {
              const def = yaml.load(fs.readFileSync(file, 'utf8'));
              if (!def?.name) { results.push(\`⏭️ Skipped \${file} — missing name\`); continue; }
              const repoName = def.name;
              try {
                // 1. Create repo
                const createBody = { name: repoName, description: def.description || '', visibility: def.visibility || 'private', private: def.visibility !== 'public', has_issues: true, has_projects: false, has_wiki: false, delete_branch_on_merge: true, auto_init: true };
                if (def.template) {
                  await api('POST', \`/repos/\${org}/\${def.template}/generate\`, { owner: org, name: repoName, description: def.description || '', private: true, include_all_branches: false });
                } else {
                  const r = await api('POST', \`/orgs/\${org}/repos\`, createBody);
                  if (r.status !== 201 && r.status !== 422) throw new Error(\`Create failed: \${JSON.stringify(r.data)}\`);
                }
                await new Promise(r => setTimeout(r, 3000));

                // 2. Topics
                if (def.topics?.length) await api('PUT', \`/repos/\${org}/\${repoName}/topics\`, { names: def.topics });

                // 3. Teams
                for (const t of (def.team_access || [])) {
                  await api('PUT', \`/orgs/\${org}/teams/\${t.team}/repos/\${org}/\${repoName}\`, { permission: t.permission });
                }

                // 4. CODEOWNERS
                const codeownersLines = (def.codeowners || []).map(r => \`\${r.pattern}    \${r.owners.join(' ')}\`);
                await upsertFile(repoName, '.github/CODEOWNERS',
                  ['# CODEOWNERS — Auto-generated by repo-factory. Changes require platform-admin review.', '', ...codeownersLines].join('\n'),
                  'chore: add CODEOWNERS [repo-factory]');

                // 5. Compliance workflow (read canonical template from governance repo)
                const tmplRes = await api('GET', \`/repos/\${govRepo}/contents/.github/templates/compliance.yml\`);
                if (tmplRes.status === 200) {
                  const complianceContent = Buffer.from(tmplRes.data.content, 'base64').toString('utf8')
                    .replace(/GOVERNANCE_REPO: ''/g, \`GOVERNANCE_REPO: '\${govRepo}'\`);
                  await upsertFile(repoName, '.github/workflows/compliance.yml', complianceContent, 'chore: add compliance workflow [repo-factory]');
                }

                // 6. PR template
                const prTemplate = ['## What does this PR do?', '', '<!-- Describe the change -->', '', '## Checklist', '', '- [ ] Tests added for new behaviour', '- [ ] No secrets committed', '- [ ] CODEOWNERS notified automatically', '- [ ] If a check fails with no fix, a waiver has been raised'].join('\n');
                await upsertFile(repoName, '.github/PULL_REQUEST_TEMPLATE.md', prTemplate, 'chore: add PR template [repo-factory]');

                // 7. Risk tier label
                const colours = { standard: '0075ca', elevated: 'e4a11b', critical: 'cf222e' };
                const tier = def.risk_tier || 'standard';
                await api('POST', \`/repos/\${org}/\${repoName}/labels\`, { name: \`risk:\${tier}\`, color: colours[tier] || '6e7781', description: \`Risk tier: \${tier}\` });

                results.push(\`✅ **\${repoName}** provisioned\\n   Teams: \${(def.team_access || []).map(t => \`\${t.team}(\${t.permission})\`).join(', ')}\\n   Risk tier: \${tier}\`);
              } catch (err) {
                core.error(\`Failed \${repoName}: \${err.message}\`);
                results.push(\`❌ **\${repoName}** failed: \${err.message}\`);
              }
            }

            const today = new Date().toISOString().split('T')[0];
            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: \`[REPO FACTORY] Provisioning summary — \${today}\`,
              body: \`## Repository Provisioning Summary\\n\\n\${results.join('\\n\\n')}\\n\\n_Auto-generated by repo-factory.yml_\`,
              labels: ['repo-provisioned']
            });"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/repo-factory.yml" "$REPO_FACTORY" \
  "chore: add repo-factory workflow [governance-setup]"

# ── team-factory.yml ───────────────────────────────────────────────────────────
step "Pushing team-factory.yml"

TEAM_FACTORY="name: \"Team Factory — Provision and Update Teams\"
on:
  push:
    branches: [main]
    paths:
      - \"teams/**.yml\"
  workflow_dispatch:
    inputs:
      team_file:
        description: \"Specific team YAML to (re-)provision\"
        required: false

jobs:
  manage-teams:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changed team definitions
        id: changed
        run: |
          if [ -n \"\${{ inputs.team_file }}\" ]; then
            echo \"files=\${{ inputs.team_file }}\" >> \"\$GITHUB_OUTPUT\"
          else
            CHANGED=\$(git diff --name-only HEAD~1 HEAD -- 'teams/*.yml' | grep -v '_template.yml' || true)
            echo \"files<<EOF\" >> \"\$GITHUB_OUTPUT\"
            echo \"\$CHANGED\" >> \"\$GITHUB_OUTPUT\"
            echo \"EOF\" >> \"\$GITHUB_OUTPUT\"
          fi

      - name: Provision teams
        if: steps.changed.outputs.files != ''
        uses: actions/github-script@v7
        env:
          FACTORY_TOKEN: \${{ secrets.REPO_FACTORY_TOKEN }}
          CHANGED_FILES: \${{ steps.changed.outputs.files }}
          ORG_NAME: \${{ vars.GITHUB_ORG_NAME }}
        with:
          github-token: \${{ secrets.GITHUB_TOKEN }}
          script: |
            const fs = require('fs');
            const yaml = require('js-yaml');
            const changedFiles = process.env.CHANGED_FILES.trim().split('\n').filter(Boolean);
            const org = process.env.ORG_NAME;
            const token = process.env.FACTORY_TOKEN;

            async function api(method, endpoint, body = null) {
              const opts = { method, headers: { Authorization: \`Bearer \${token}\`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' } };
              if (body) opts.body = JSON.stringify(body);
              const res = await fetch(\`https://api.github.com\${endpoint}\`, opts);
              const text = await res.text();
              return { status: res.status, data: text ? JSON.parse(text) : {} };
            }

            const results = [];
            for (const file of changedFiles) {
              const def = yaml.load(fs.readFileSync(file, 'utf8'));
              if (!def?.slug) { results.push(\`⏭️ Skipped \${file} — missing slug\`); continue; }
              try {
                const teamBody = { name: def.name, description: def.description || '', privacy: def.privacy || 'closed' };
                if (def.parent_team) {
                  const p = await api('GET', \`/orgs/\${org}/teams/\${def.parent_team}\`);
                  if (p.status === 200) teamBody.parent_team_id = p.data.id;
                }
                const existing = await api('GET', \`/orgs/\${org}/teams/\${def.slug}\`);
                if (existing.status === 200) {
                  await api('PATCH', \`/orgs/\${org}/teams/\${def.slug}\`, teamBody);
                } else {
                  await api('POST', \`/orgs/\${org}/teams\`, { ...teamBody, org });
                }
                for (const u of (def.maintainers || [])) {
                  if (u) await api('PUT', \`/orgs/\${org}/teams/\${def.slug}/memberships/\${u}\`, { role: 'maintainer' });
                }
                for (const u of (def.members || [])) {
                  if (u) await api('PUT', \`/orgs/\${org}/teams/\${def.slug}/memberships/\${u}\`, { role: 'member' });
                }
                results.push(\`✅ **\${def.name}** (\${def.slug}) — maintainers: \${(def.maintainers||[]).join(', ')||'none'} | members: \${(def.members||[]).join(', ')||'none'}\`);
              } catch (err) {
                results.push(\`❌ **\${def.name}** failed: \${err.message}\`);
              }
            }
            const today = new Date().toISOString().split('T')[0];
            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: \`[TEAM FACTORY] Summary — \${today}\`,
              body: \`## Team Provisioning Summary\\n\\n\${results.join('\\n\\n')}\\n\\n_Auto-generated by team-factory.yml_\`,
              labels: ['team-provisioned']
            });"

push_file "$PLATFORM_ORG" "$GOVERNANCE_REPO" \
  ".github/workflows/team-factory.yml" "$TEAM_FACTORY" \
  "chore: add team-factory workflow [governance-setup]"

success "Repo Factory and Team Factory workflows pushed"
