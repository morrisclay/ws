# {{name}} — Theme Research

## Purpose
Deep-dive research workspace for investment theme analysis. Focused on thorough, evidence-based technology and market assessment.

## Structure
- `research/` — Research memos, thesis documents, landscape maps
- `data/` — Raw data, company lists, datasets
- `output/` — Final deliverables, investment memos, presentations

## Workflow
1. Define the investment thesis or research question
2. Map the landscape: key companies, technologies, trends
3. Deep-dive on technical feasibility and market dynamics
4. Synthesize into structured memos in `research/`
5. Produce final deliverables in `output/`

## Journal

This workspace uses `.journal.jsonl` for continuity across sessions. On startup, read the last 20 entries to understand where work left off.

Log important events during your session:
```bash
ws journal {{name}} --finding "TAM estimated at $4.2B by 2028 (Gartner)"
ws journal {{name}} --question "Conflicting data between CB Insights and Gartner"
ws journal {{name}} --decision "Focusing on North American market first"
ws journal {{name}} --note "Created landscape map in research/"
```

Entry types: `finding`, `open_question`, `decision`, `note`, `stage_change`

## Conventions
- Every claim needs a source citation
- Date all files: `YYYY-MM-DD-topic.md`
- Distinguish facts from inferences
- Track company mentions with consistent naming
- Save everything — never discard raw data
