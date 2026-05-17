---
name: governance-admin-report
version: "1.0"
description: >
  Generate an admin access report showing current organisation owners, repos with
  direct admin collaborators (anti-pattern), teams with admin permissions, and
  recent admin changes from the audit log. Use when a user asks for "admin report",
  "who has admin access", "list org owners", "show admin changes", "access review",
  or "privilege report". Non-interactive — runs and prints results immediately.
triggers:
  - "admin report"
  - "who has admin access"
  - "list org owners"
  - "show admin changes"
  - "access review"
  - "privilege report"
  - "show org admins"
script: ../reports/admin-report.sh
---

# Skill: Admin Access Report

## What This Skill Does

Pulls live data from the GitHub API to show:
1. **Current org owners** (all users with Owner role)
2. **Direct admin collaborators** on repos (anti-pattern — should be via teams)
3. **Teams with admin permission** on specific repos
4. **Recent admin changes** from the audit log (requires enterprise slug)
5. **platform-admins team members** with their maintainer/member role

This report is intended for periodic access reviews and compliance evidence.

**This script is READ-ONLY. It makes no changes.**

---

## Execution

### Basic (org-level only)
```bash
cd governance-scripts
bash reports/admin-report.sh
```

### With enterprise audit log (recommended)
```bash
bash reports/admin-report.sh --enterprise my-enterprise-slug
```

### Override org
```bash
bash reports/admin-report.sh --org my-org-name
```

---

## Interpreting Results

### Section: Direct Admin Collaborators
```
⚠  payments-service
   ! john-doe (direct admin — should be via team)
```
Any user listed here should be removed as a direct collaborator and granted
access via a team instead. Raise a finding with the repo owner.

### Section: Teams with Admin Permission
```
platform-admins has admin on:
  • github-governance
  • .github
```
Only `platform-admins` should appear here. Any other team with admin on repos
is a finding — report to the security team.

### Section: Admin Changes (Audit Log)
Shows additions/removals of org members and team members in the last 30 days.
Any unexpected changes should be investigated.

---

## Saving Report Output

```bash
bash reports/admin-report.sh --enterprise my-enterprise > "admin-report-$(date +%Y%m%d).txt"
```

For compliance evidence, save and upload to your GRC tool or attach to the
audit issue in the governance repo.

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `Could not fetch org owners` | Token missing `read:org` | `gh auth refresh -s read:org` |
| `Could not fetch platform-admins team` | Team doesn't exist yet | Run `bash setup-all.sh --step 9` |
| Audit log section blank | No enterprise slug set | Pass `--enterprise <slug>` |
| Rate limit hit | Many repos scanned | Wait 60 seconds and re-run with `--org` |
