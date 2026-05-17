---
name: governance-audit-query
version: "1.0"
description: >
  Run interactive audit log queries against GitHub's audit log for compliance and
  investigation purposes. Use when a user asks to "query the audit log", "search
  audit events", "show who did X", "audit log for admin changes", "find ruleset
  bypasses", "check secret changes", "export audit log", or any investigation of
  GitHub activity history. Launches an interactive menu with 10 query types and
  optional CSV export.
triggers:
  - "query audit log"
  - "search audit events"
  - "audit log"
  - "who created this repo"
  - "find ruleset bypasses"
  - "check secret changes"
  - "export audit log"
  - "audit investigation"
  - "show dismissed alerts"
script: ../reports/audit-query.sh
---

# Skill: Interactive Audit Log Query

## What This Skill Does

Launches an **interactive 10-item query menu** against GitHub's audit log
(organisation-level or enterprise-level). Covers the most common compliance and
security investigation needs. Supports optional CSV export for each query.

**This script is READ-ONLY. It makes no changes.**

---

## Execution

### Standard (uses org-level audit log)
```bash
cd governance-scripts
bash reports/audit-query.sh
```

### With enterprise audit log (full historical depth, cross-org)
```bash
bash reports/audit-query.sh --enterprise my-enterprise-slug
```

### Override org
```bash
bash reports/audit-query.sh --org my-org-name
```

---

## Menu Options

| # | Query | Common use case |
|---|-------|----------------|
| 1 | Admin / owner changes | Access review — who was granted/removed admin |
| 2 | Branch protection & ruleset bypasses | Security investigation — who bypassed rules |
| 3 | New repository creation | Asset inventory — what repos were created |
| 4 | Secret changes (Actions / Dependabot) | Credentials review — new/deleted secrets |
| 5 | Webhook additions and removals | Integrations audit — unauthorised webhooks |
| 6 | Dismissed GHAS / Dependabot alerts | Security findings — who dismissed alerts and why |
| 7 | App (OAuth / GitHub App) installations | Third-party access review |
| 8 | Team membership changes | Access governance — team joins/departures |
| 9 | Repository settings changes | Compliance — who changed merge settings |
| 10 | All events (broad export) | Full audit period export to CSV |

---

## Date Range

On launch, the script asks for a lookback window:
```
Number of days to look back [default: 7]:
```

Enter a number (e.g. `30` for last 30 days, `90` for quarterly review).

---

## CSV Export

After any query, the script offers CSV export:
```
Export this query to CSV? [y/N]:
```

If `y`, a file named `audit-export-YYYYMMDD-HHMMSS.csv` is created in the
current directory with columns: `timestamp, actor, action, target, country, data`.

---

## Interpreting Results

Each query result shows:
```
TIMESTAMP          ACTOR                    ACTION                         TARGET
──────────────────────────────────────────────────────────────────────────────────
2026-05-10T14:23   john-doe                 org.add_member                 my-org
2026-05-12T09:41   jane-smith               protected_branch.bypass        my-org/payments-svc
```

Items to escalate immediately:
- `bypass_push_rulesets` / `bypass_branch_protections` — investigate every bypass
- `secret.destroy` — check if credential was rotated before deletion
- `code_scanning_alert.dismissed` — verify dismissal reason is legitimate
- `integration_installation.create` — verify the installed app was approved

---

## Saving Output for Evidence

```bash
bash reports/audit-query.sh --enterprise my-enterprise 2>&1 | tee "audit-session-$(date +%Y%m%d).txt"
```

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| Empty results | No events matching query in time range | Widen date range or try a broader query (#10) |
| `403 Forbidden` on enterprise | Token missing `read:audit_log` enterprise scope | `gh auth refresh -s read:audit_log` |
| CSV export empty | Enterprise audit log not available at org tier | Requires GitHub Enterprise Cloud |
| `jq: error` | Unexpected API response shape | Check `gh` CLI version (`gh --version` ≥ 2.40) |
