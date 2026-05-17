---
name: governance-waiver-status
version: "1.0"
description: >
  Show the current compliance waiver dashboard — pending approvals, active waivers
  with expiry countdowns, and waivers expiring soon. Use when a user asks for
  "waiver status", "show waivers", "active waivers", "pending waivers", "compliance
  exceptions", "waiver report", or "expiring waivers". Non-interactive — runs and
  prints a colour-coded dashboard immediately.
triggers:
  - "waiver status"
  - "show waivers"
  - "active waivers"
  - "pending waivers"
  - "compliance exceptions"
  - "waiver report"
  - "expiring waivers"
  - "waiver dashboard"
script: ../reports/waiver-status.sh
---

# Skill: Compliance Waiver Status Dashboard

## What This Skill Does

Queries open issues labelled `waiver-pending` and `waiver-approved` in the governance
repo and displays a colour-coded dashboard:

| Colour | Meaning |
|--------|---------|
| 🟡 Yellow | Pending approval (not yet approved) |
| 🟢 Green | Active waiver, expiry > 7 days |
| 🟡 Yellow | Active waiver, expiry in < 7 days (⚠ expiring soon) |
| 🔴 Red | Overdue — expiry date has passed |

**This script is READ-ONLY. It makes no changes.**

---

## Execution

### Standard (pending + active + expiring)
```bash
cd governance-scripts
bash reports/waiver-status.sh
```

### Include recently expired/rejected (last 14 days)
```bash
bash reports/waiver-status.sh --all
```

### Filter by repository
```bash
bash reports/waiver-status.sh --repo payments-service
```

---

## Interpreting the Dashboard

### Pending Approval
```
Issue  Title                                     Opened       URL
──────────────────────────────────────────────────────────────
#42    Waiver: CodeQL / Analyze — payments-svc   2026-05-10   https://github.com/...
```
These waivers are waiting for a risk owner to comment `/approve-waiver`.

### Active Approved Waivers
```
Issue  Title                                 Opened       Expires      Status
──────────────────────────────────────────────────────────────────────────────
#38    Waiver: Nexus IQ — legacy-service      2026-04-20   2026-06-01   ✓ active
#41    Waiver: CodeQL — auth-service          2026-05-01   2026-05-25   ⚠ expiring soon
```

### Summary Line
```
Summary:  Pending: 1  |  Active: 4  |  Expiring soon: 1
```

---

## Actions to Take Based on Results

| Finding | Action |
|---------|--------|
| Pending waivers > 48h old | Chase risk owner for `/approve-waiver` comment |
| Waiver expiring in < 7 days | Remind team to fix the underlying issue or request extension |
| Overdue waiver (red) | Pipeline should already be blocked — escalate to team lead |
| Active waivers growing week-on-week | Flag to compliance team; consider tightening controls |

---

## Saving for Compliance Evidence

```bash
bash reports/waiver-status.sh --all > "waiver-report-$(date +%Y%m%d).txt"
```

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| Empty output | No issues labelled `waiver-approved` or `waiver-pending` | Correct — no waivers open |
| `GOVERNANCE_REPO not set` | Config not loaded | Run `source ~/.github-governance-setup.env` |
| Expiry shows "unknown" | Waiver title missing `[EXPIRES:YYYY-MM-DD]` | Waiver was created incorrectly — check issue template |
