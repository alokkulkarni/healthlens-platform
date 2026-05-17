# GitHub Enterprise Governance Scripts

Automation scripts to provision and maintain the entire governance framework described in the
**GitHub Enterprise Risk & Audit Guide**. All scripts use the `gh` CLI and GitHub REST API,
are interactive where mandatory input is needed, and are **idempotent** (safe to re-run).

---

## Prerequisites

| Tool | Minimum version | Check |
|------|-----------------|-------|
| `gh` CLI | 2.40+ | `gh --version` |
| `jq` | 1.6+ | `jq --version` |
| `git` | any recent | `git --version` |
| `base64` | (macOS or GNU coreutils) | `base64 --version` |

**Authentication:** Run `gh auth login` once before any script. Your token needs:
- `read:org`, `write:org`, `admin:org`
- `repo` (to push files to the governance repo)
- `read:audit_log` (for audit query scripts)
- `admin:enterprise` (optional — only for enterprise-level audit log)

---

## Quick Start (First-time setup)

Run the master orchestrator once. It collects all config, saves it to
`~/.github-governance-setup.env`, and runs all 10 setup steps in order.

```bash
cd governance-scripts
bash setup-all.sh
```

You will be prompted for:
- GitHub Organisation name (the engineering org where apps live)
- Platform Organisation name (where the governance repo lives — can be the same)
- Governance repo name (default: `github-governance`)
- Enterprise slug (optional — enables enterprise-level audit log queries)
- Admin email address

**Running a single step again:**
```bash
bash setup-all.sh --step 4       # re-run only step 4 (compliance workflow)
```

---

## Day-to-day Commands

### New Repository Request
```bash
bash factory/new-repo.sh
```
Interactive 10-step wizard. Generates a YAML definition and opens a PR to the governance repo.
On merge, the `repo-factory.yml` workflow auto-provisions the repo.

### New Team Request
```bash
bash factory/new-team.sh
```
Creates or updates a team. Prompts for name, slug, privacy, parent team, maintainers, and members.
Opens a PR to the governance repo.

### Sync Compliance Workflow to All Repos
```bash
# Preview changes (no writes)
bash factory/sync-compliance.sh --dry-run

# Apply to all repos
bash factory/sync-compliance.sh

# Update a single repo only
bash factory/sync-compliance.sh --repo my-app
```

### View Current Waiver Status
```bash
# Active and pending waivers
bash reports/waiver-status.sh

# Include expired/rejected waivers
bash reports/waiver-status.sh --all

# Filter by repo
bash reports/waiver-status.sh --repo payments-service
```

### Admin Access Report
```bash
bash reports/admin-report.sh
```
Shows current org owners, repos with direct admin collaborators (anti-pattern), teams with admin
permission, platform-admins team members, and recent audit log admin events.

```bash
# Include enterprise audit log
bash reports/admin-report.sh --enterprise my-enterprise-slug
```

### Interactive Audit Log Query
```bash
bash reports/audit-query.sh
```
Numbered menu covering: admin changes, branch protection bypasses, repo creation, secret changes,
webhook events, dismissed alerts, app installs, team changes, settings changes. Optional CSV export.

---

## Setup Steps Reference

| Step | Script | What it does |
|------|--------|-------------|
| 01 | `setup/01-org-policies.sh` | Sets org-level policies (private forks, Actions permissions, 2FA requirement) |
| 02 | `setup/02-governance-repo.sh` | Creates the governance repo with branch protection |
| 03 | `setup/03-waiver-workflows.sh` | Pushes all 5 waiver system files (issue template, 4 workflows) |
| 04 | `setup/04-compliance-workflow.sh` | Pushes canonical `compliance.yml` template + CODEOWNERS |
| 05 | `setup/05-factory-workflows.sh` | Pushes `repo-factory.yml`, `team-factory.yml`, definition templates |
| 06 | `setup/06-audit-workflow.sh` | Pushes `central-audit-report.yml` workflow |
| 07 | `setup/07-rulesets.sh` | Creates org-level branch protection rulesets |
| 08 | `setup/08-labels.sh` | Creates all compliance, waiver, risk, and review labels |
| 09 | `setup/09-base-teams.sh` | Creates base teams: platform-admins, security-reviewers, compliance-team |
| 10 | `setup/10-finalize.sh` | Prints final checklist and verifies setup |

---

## Directory Structure

```
governance-scripts/
├── setup-all.sh              ← Master orchestrator
├── lib/
│   └── common.sh             ← Shared utilities (colours, prompts, push_file, etc.)
├── setup/
│   ├── 01-org-policies.sh
│   ├── 02-governance-repo.sh
│   ├── 03-waiver-workflows.sh
│   ├── 04-compliance-workflow.sh
│   ├── 05-factory-workflows.sh
│   ├── 06-audit-workflow.sh
│   ├── 07-rulesets.sh
│   ├── 08-labels.sh
│   ├── 09-base-teams.sh
│   └── 10-finalize.sh
├── factory/
│   ├── new-repo.sh           ← Interactive: request a new repo
│   ├── new-team.sh           ← Interactive: create/update a team
│   └── sync-compliance.sh    ← Push updated compliance.yml to all repos
└── reports/
    ├── admin-report.sh       ← Current admin access + recent changes
    ├── waiver-status.sh      ← Active/pending/expiring waiver dashboard
    └── audit-query.sh        ← Interactive audit log menu with CSV export
```

---

## Secrets Required

Set these at the **organisation level** in GitHub (Settings → Secrets → Actions → Organisation secrets):

| Secret name | Scope | Used by |
|-------------|-------|---------|
| `GOVERNANCE_READ_TOKEN` | All repos | `waiver-check.yml` in every app repo |
| `REPO_FACTORY_TOKEN` | Governance repo | `repo-factory.yml`, `team-factory.yml` |
| `AUDIT_REPORT_TOKEN` | Governance repo | `central-audit-report.yml` |
| `SONAR_TOKEN` | All repos | `compliance.yml` SonarQube step |
| `SONAR_HOST_URL` | All repos | `compliance.yml` SonarQube step |
| `NEXUS_IQ_URL` | All repos | `compliance.yml` Nexus IQ step |
| `NEXUS_IQ_USERNAME` | All repos | `compliance.yml` Nexus IQ step |
| `NEXUS_IQ_PASSWORD` | All repos | `compliance.yml` Nexus IQ step |
| `STAGING_APP_URL` | All repos | `compliance.yml` DAST step |

**Repository variable required on governance repo:**

| Variable | Value |
|----------|-------|
| `GITHUB_ORG_NAME` | The engineering org where repos are provisioned |

---

## Troubleshooting

**`gh: command not found`**
Install the GitHub CLI: https://cli.github.com

**`jq: command not found`**
macOS: `brew install jq` | Ubuntu: `apt-get install jq`

**`Error: Resource not accessible by integration`**
Your token is missing a scope. Run `gh auth refresh -s admin:org,read:audit_log,repo`.

**`push_file: 422 Unprocessable Entity`**
The file already exists and the SHA wasn't retrieved (usually a permissions issue).
Check your token has `repo` scope on the governance repo.

**Waiver check returning false positives**
Ensure `GOVERNANCE_READ_TOKEN` has `issues:read` on the governance repo, not just the org.

**Factory workflow not triggering**
The `paths:` filter in `repo-factory.yml` requires changes to `repos/**/*.yml`.
Ensure the new-repo PR only touches files in the `repos/` directory.

---

## Full Documentation

See the complete step-by-step admin guide:
`~/.copilot/session-state/*/files/github-enterprise-risk-audit-guide.md`

Or view it in your session files directory after initial setup.
