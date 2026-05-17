---
name: governance-new-team
version: "1.0"
description: >
  Create or update a GitHub team through the governance factory. Use when a user
  asks to "create a new team", "add a team", "provision a team", "set up a team
  in GitHub", or "update team members". Runs the interactive new-team.sh wizard
  which collects team details, generates a YAML definition, and opens a Pull Request
  to the governance repo. Teams are never created directly — always via PR.
triggers:
  - "create a new team"
  - "add a team"
  - "provision a team"
  - "set up a team"
  - "update team members"
  - "new github team"
script: ../factory/new-team.sh
---

# Skill: New Team Request

## What This Skill Does

Launches the **interactive team creation wizard**. The wizard:
1. Validates the team slug (unique, lowercase/hyphens)
2. Detects if the team already exists (offers update path)
3. Collects visibility, parent team, maintainers, members
4. Generates a YAML definition in `teams/<slug>.yml`
5. Clones the governance repo, creates a branch, commits, and opens a PR

**Do NOT create teams via `gh api` or `gh team` directly.
All team creation must flow through the governance PR process.**

---

## Execution

```bash
cd governance-scripts
bash factory/new-team.sh
```

**The script is fully interactive.** Let the wizard guide the user.

---

## Wizard Steps

| Step | What is asked |
|------|--------------|
| 1 | Team display name (e.g. `Payments Backend`) |
|   | Team slug (auto-generated from name; user can override) |
|   | If slug exists → offer to update existing team |
|   | Team description |
| 2 | Visibility: `closed` (visible to all org members) or `secret` |
| 3 | Parent team slug (optional; for nested team hierarchy) |
| 4 | Maintainers (iterative; at least one required) |
|   | Members (iterative; blank to finish) |
| 5 | Requester username + business justification |
| Preview + confirm → PR created |

---

## Visibility Guide (share with user if they ask)

| Option | When to use |
|--------|------------|
| `closed` | Most teams — visible to all org members, discoverable |
| `secret` | Security teams, incident response — hidden from non-members |

---

## Parent Team Hierarchy (example)

```
engineering (parent)
├── payments-backend
├── identity-platform
└── data-platform (parent)
    ├── data-engineering
    └── ml-platform
```

---

## Expected Output

```
[SUCCESS] Pull Request created: https://github.com/<platform-org>/<governance-repo>/pull/<N>
```

On PR approval and merge, `team-factory.yml` workflow auto-provisions the team
and adds all listed maintainers and members.

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `Slug validation failed` | Name contains uppercase or spaces | Use lowercase-with-hyphens slug |
| `Parent team not found` | Parent doesn't exist | Create parent team first |
| `No maintainers provided` | Script exits early | At least one maintainer is required |
| `git push failed` | No write access to governance repo | Check PAT `repo` scope |
