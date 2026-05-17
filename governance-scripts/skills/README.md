# Governance Skills — Agent Reference

Skills in this directory are structured instructions for AI agents. Each skill
tells the agent **which script to run and how** — agents must execute the referenced
script rather than interpreting or reimplementing the task themselves.

---

## Skill Inventory

| Skill file | Script | Interactive | Read-only |
|------------|--------|:-----------:|:---------:|
| [governance-setup.md](governance-setup.md) | `../setup-all.sh` | ✓ | |
| [new-repo.md](new-repo.md) | `../factory/new-repo.sh` | ✓ | |
| [new-team.md](new-team.md) | `../factory/new-team.sh` | ✓ | |
| [sync-compliance.md](sync-compliance.md) | `../factory/sync-compliance.sh` | | |
| [admin-report.md](admin-report.md) | `../reports/admin-report.sh` | | ✓ |
| [waiver-status.md](waiver-status.md) | `../reports/waiver-status.sh` | | ✓ |
| [audit-query.md](audit-query.md) | `../reports/audit-query.sh` | ✓ | ✓ |

Machine-readable discovery: [manifest.json](manifest.json)

---

## Quick Trigger Reference

| If a user says… | Run this skill |
|-----------------|----------------|
| "set up governance" / "bootstrap governance" | `governance-setup` |
| "create a new repo" / "request a repository" | `governance-new-repo` |
| "create a team" / "add a team" | `governance-new-team` |
| "sync compliance" / "push compliance.yml" | `governance-sync-compliance` |
| "admin report" / "who has admin access" | `governance-admin-report` |
| "waiver status" / "show waivers" | `governance-waiver-status` |
| "query audit log" / "audit investigation" | `governance-audit-query` |

---

## Agent Rules

1. **Always run the script** — never manually call GitHub API endpoints to replicate
   what a script already does. The scripts handle validation, idempotency, and
   consistent output formatting.

2. **Interactive scripts** — if marked `interactive: true` in the manifest, the agent
   must launch the script and allow the user to answer prompts in the terminal.
   Do not attempt to pre-fill or automate the answers.

3. **Non-interactive scripts** — if marked `interactive: false`, the agent may pass
   flags as needed (`--dry-run`, `--repo`, `--enterprise`, etc.) based on what the
   user asked.

4. **Read-only scripts** — if marked `readonly: true`, the agent can confidently
   run these without fear of side effects. They never write to GitHub.

5. **Prerequisite check** — before running any script, verify:
   ```bash
   gh auth status
   ```
   If not authenticated, prompt the user to run `gh auth login` first.

6. **Working directory** — all scripts must be run from the `governance-scripts/`
   directory:
   ```bash
   cd governance-scripts
   bash <path-to-script>.sh
   ```

---

## Skill File Format

Each skill `.md` file contains:

```yaml
---
name: skill-name         # machine identifier
version: "1.0"
description: >           # agent trigger matching description (keep detailed)
  ...
triggers:                # phrase list for intent matching
  - "phrase one"
script: ../path/to/script.sh
---
```

Followed by human and agent-readable sections:
- **What This Skill Does** — overview
- **Execution** — exact `bash` commands with flags
- **Expected Output** — what success looks like
- **Error Handling** — table of errors, causes, and resolutions

---

## Adding a New Skill

1. Create a new `.sh` script in `../setup/`, `../factory/`, or `../reports/`
2. Copy a skill `.md` file as a template
3. Update all sections including the YAML frontmatter
4. Add an entry to `manifest.json`
5. Add a row to the table in this file
