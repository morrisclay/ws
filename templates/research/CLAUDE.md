# {{name}} — Research

## Purpose
Research workspace for [TOPIC]. Focused on thorough, evidence-based analysis.

## Structure
- `research/` — Research memos and findings
- `data/` — Raw data, datasets, extractions
- `output/` — Final deliverables, reports

## Workflow
1. Define the research question clearly
2. Gather evidence from multiple sources
3. Synthesize findings into structured memos in `research/`
4. Produce final output in `output/`

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
- Save everything — never discard raw data
