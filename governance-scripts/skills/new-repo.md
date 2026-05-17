---
name: governance-new-repo
version: "1.0"
description: >
  Create a new repository request through the governance factory. Use when a user
  asks to "create a new repo", "request a new repository", "provision a new service
  repo", "add a repository to the org", or "open a repo creation PR". Runs the
  interactive new-repo.sh wizard which validates input, generates a YAML definition,
  and opens a Pull Request to the governance repo for admin approval.
triggers:
  - "create a new repo"
  - "request a new repository"
  - "provision a repo"
  - "add a repository"
  - "new service repo"
  - "open a repo creation PR"
script: ../factory/new-repo.sh
---

# Skill: New Repository Request

## What This Skill Does

Launches the **interactive 10-step repository creation wizard**. The wizard:
1. Validates the repo name (lowercase, hyphens only, no duplicates)
2. Collects description, visibility, risk tier, business domain
3. Prompts for team access assignments
4. Builds the CODEOWNERS file
5. Generates a YAML definition
6. Clones the governance repo, creates a branch, commits, and opens a PR

**Do NOT create repos directly via `gh repo create` or API calls.
Always route through this script to ensure governance compliance.**

---

## Execution

```bash
cd governance-scripts
bash factory/new-repo.sh
```

**The script is fully interactive.** Do not pass arguments or pre-fill answers.
Let the wizard prompt the user for each field.

---

## Wizard Steps (for agent awareness — do not skip or automate)

| Step | What is asked |
|------|--------------|
| 1 | Repository name (validated: lowercase/hyphens, existence check against org) |
| 2 | Description |
| 3 | Visibility: `private` / `internal` / `public` (public requires justification) |
| 4 | Risk tier: `standard` / `elevated` / `critical` |
| 5 | Business domain and topics |
| 6 | Starter template (optional) |
| 7 | Team access (iterative — enter team slugs one at a time; blank to finish) |
| 8 | CODEOWNERS (default owner required; additional patterns optional) |
| 9 | Requester username and business justification |
| 10 | YAML preview → confirm → PR created |

---

## Expected Output

```
[SUCCESS] Pull Request created: https://github.com/<platform-org>/<governance-repo>/pull/<N>
```

On approval and merge of that PR, the `repo-factory.yml` GitHub Actions workflow
automatically provisions the repository.

---

## Post-Execution

Tell the user:
- PR URL where they can track approval
- The repository will be created automatically after an admin approves the PR
- They can add team members via `bash factory/new-team.sh` if new teams are needed

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `Repo already exists` | Duplicate name check failed | Choose a different name |
| `Team not found` | Team slug doesn't exist yet | Create team first with `new-team.sh` |
| `git clone failed` | Missing access to governance repo | Verify PAT has `repo` scope |
| `gh pr create failed` | Branch already exists | Script auto-appends timestamp to branch name; retry |
