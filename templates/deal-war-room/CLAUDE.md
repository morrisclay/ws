# {{name}} — Deal War Room

## Purpose
Due diligence workspace for evaluating [COMPANY/DEAL]. Structured for rapid, thorough assessment.

## Structure
- `diligence/` — Due diligence workstreams
  - `team/` — Founder and team analysis
  - `market/` — Market size, dynamics, competition
  - `product/` — Product analysis, technical assessment
  - `financials/` — Financial analysis, projections
- `materials/` — Pitch decks, data rooms, received documents
- `notes/` — Meeting notes, call logs, Q&A

## Workflow
1. Initial screening: company overview, team, market
2. Deep dive: product, technology, competitive landscape
3. Financial analysis: unit economics, projections, comparables
4. Reference checks and expert calls (log in `notes/`)
5. Investment memo in `diligence/`

## Journal

This workspace uses `.journal.jsonl` for continuity across sessions. On startup, read the last 20 entries to understand where work left off.

Log important events during your session:
```bash
ws journal {{name}} --finding "Revenue growing 40% YoY per latest filing"
ws journal {{name}} --question "Need to verify Series B valuation claim"
ws journal {{name}} --decision "Pass on this deal — unit economics don't work"
ws journal {{name}} --note "Call with CTO scheduled for Thursday"
```

Entry types: `finding`, `open_question`, `decision`, `note`, `stage_change`

## Conventions
- Date all files: `YYYY-MM-DD-topic.md`
- Log every interaction in `notes/`
- Cite all data sources
- Flag risks explicitly with [RISK] tag
- Distinguish confirmed facts from assumptions
