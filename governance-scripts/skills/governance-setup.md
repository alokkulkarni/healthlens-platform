---
name: governance-setup
version: "1.0"
description: >
  Run the full GitHub Enterprise governance framework setup for an organisation.
  Use when a user asks to "set up governance", "initialise the governance repo",
  "run governance setup", "configure GitHub Enterprise governance", or
  "provision the compliance framework". Executes setup-all.sh which provisions
  the governance repo, waiver system, compliance workflows, factory workflows,
  audit reporting, rulesets, labels, and base teams — in the correct order.
triggers:
  - "set up governance"
  - "run governance setup"
  - "initialise governance"
  - "configure github enterprise governance"
  - "provision compliance framework"
  - "bootstrap governance"
script: ../setup-all.sh
---

# Skill: GitHub Enterprise Governance Setup

## What This Skill Does

Runs the complete 10-step governance framework setup. This is a one-time (or
repeat-safe idempotent) operation that provisions everything required for the
GitHub Enterprise governance model described in the guide.

**Do NOT interpret or reimplement any steps manually. Run the script.**

---

## Prerequisites (verify before running)

```bash
gh --version       # must be 2.40+
jq --version       # must be 1.6+
gh auth status     # must show logged-in with admin:org, repo, read:audit_log scopes
```

If any prerequisite fails, tell the user what is missing and how to fix it. Do not
proceed until all prerequisites pass.

---

## Execution

### Full setup (all steps)
```bash
cd governance-scripts
bash setup-all.sh
```

The script is **interactive** — it will prompt for:
- GitHub Organisation name
- Platform Organisation name (governance repo owner)
- Governance repository name (default: `github-governance`)
- Enterprise slug (optional — for audit log)
- Admin email address

**Do not pre-fill these values.** Let the script prompt the user in the terminal.

### Resume from a specific step
```bash
bash setup-all.sh --step 4
```

Valid step numbers: 1–10.

---

## Monitoring Progress

The script uses coloured output:
- 🔵 `[INFO]` — informational
- ✅ `[SUCCESS]` — step completed
- ⚠️  `[WARN]` — non-fatal warning, step may continue
- ❌ `[ERROR]` — step failed, script exits

Watch for `ERROR` lines. If the script exits early, note the step number and
error message, then run `bash setup-all.sh --step <N>` to resume.

---

## Expected Completion Output

A successful run ends with:
```
[SUCCESS] Governance framework setup complete!
```

Followed by the finalize script printing a verification checklist. All items
should show ✓.

---

## After Setup

Tell the user:
1. Configuration saved to `~/.github-governance-setup.env`
2. Governance repo is live at `https://github.com/<platform-org>/<governance-repo>`
3. Required secrets must be added manually (listed in `README.md`)
4. Run `bash reports/waiver-status.sh` to verify the waiver system is active

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `Resource not accessible` | Token missing scope | `gh auth refresh -s admin:org,repo` |
| `422 Unprocessable Entity` | File SHA mismatch | Re-run the same step — `push_file` is idempotent |
| `Repo already exists` | Step 2 safe to skip | Script handles this; continue |
| `Team already exists` | Step 9 safe to skip | Script handles this; continue |
