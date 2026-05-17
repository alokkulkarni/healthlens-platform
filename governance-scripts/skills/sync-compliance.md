---
name: governance-sync-compliance
version: "1.0"
description: >
  Push the latest compliance.yml workflow to all repositories in the organisation.
  Use when a user asks to "sync compliance", "update compliance workflow",
  "push compliance.yml to all repos", "propagate governance updates", or
  "update the pipeline in all repos". Runs sync-compliance.sh which reads the
  canonical template from the governance repo and writes it to every non-archived repo.
triggers:
  - "sync compliance"
  - "update compliance workflow"
  - "push compliance.yml"
  - "propagate governance"
  - "update pipeline in all repos"
  - "sync governance changes"
script: ../factory/sync-compliance.sh
---

# Skill: Sync Compliance Workflow

## What This Skill Does

Reads the canonical `compliance.yml` template from `.github/templates/compliance.yml`
in the governance repo, substitutes the `GOVERNANCE_REPO` placeholder with the real
value, then writes `.github/workflows/compliance.yml` to every non-archived repo in
the organisation.

**Do NOT manually edit compliance.yml in individual repos.
Always update the template in the governance repo and run this sync.**

---

## When to Run

- After updating the canonical `compliance.yml` template in the governance repo
- After onboarding new repositories that were not yet covered
- After adding a new scanner (e.g. new DAST rule) to the template
- On a scheduled cadence (monthly) to ensure drift doesn't occur

---

## Execution

### Safe preview first (always recommended)
```bash
cd governance-scripts
bash factory/sync-compliance.sh --dry-run
```

Shows which repos would be updated without making any changes.

### Apply to all repos
```bash
bash factory/sync-compliance.sh
```

### Apply to a single repo only
```bash
bash factory/sync-compliance.sh --repo my-service-name
```

### Combine flags
```bash
bash factory/sync-compliance.sh --dry-run --repo my-service-name
```

---

## Expected Output

```
[SUCCESS] my-service             ← file written/updated
[INFO]    Skipping: github-governance   ← governance repo itself is skipped
...
──────────────────────────────────
✓  Updated:  42 repos
–  Skipped:  1 repos
```

If failures appear (`✗ Failed:`), check that:
1. The token has `repo` write access to those repositories
2. The repos have `main` as their default branch

---

## Rate Limiting

The script paces at 2 repos/second. For large organisations (>200 repos) this may
take several minutes. Do not interrupt mid-run; the script is safe to re-run.

---

## After Sync

Tell the user:
- Changes are committed directly to `main` in each app repo with message
  `chore: update compliance workflow [governance-sync]`
- Engineers will see the updated workflow on their next PR
- No PRs are opened in app repos — this is a platform push

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `Could not fetch compliance template` | Template missing from governance repo | Run `bash setup-all.sh --step 4` first |
| `Failed: <repo-name>` | No write access to that repo | Add governance PAT as collaborator or use `REPO_FACTORY_TOKEN` |
| `422` on some repos | Default branch is not `main` | Pass `--repo` and handle manually |
