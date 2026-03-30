# {{name}}

## Purpose
[Describe this project's purpose]

## Structure
[Document the project structure as it evolves]

## Session Lifecycle

### On Session Start (MANDATORY)
1. Read the last 20 journal entries: `tail -n 20 .journal.jsonl` (if it exists)
2. Search the knowledge layer for prior context on the current topic: `knowledge__search_knowledge`
3. Verify environment is loaded: check that `.env` exists and key vars are set

### During Work
Log significant events to `.journal.jsonl` as they happen — don't batch:
```bash
# Append a journal entry (replace TYPE and TEXT)
printf '{"ts":"%s","type":"%s","text":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "TYPE" "TEXT" >> .journal.jsonl
```
Entry types: `finding`, `open_question`, `decision`, `note`, `stage_change`

Capture non-obvious insights to the knowledge layer proactively (see below).

### On Session End (MANDATORY)
1. Write a journal `note` summarizing what was accomplished and what's next
2. Capture any strategic insights to the knowledge layer
3. If there are open questions, log them as `open_question` entries

## Auto-Knowledge Capture

When working in this workspace, proactively use the knowledge MCP plugin to build a persistent, searchable knowledge base. The goal is passive accumulation -- capture without being asked.

### When to capture insights (knowledge__capture_insight)
- After strategic discussions: capture key conclusions, signals, and hypotheses
- After research (web search, email, Linear): capture non-obvious findings
- When a decision is made or a strong opinion is formed: capture the reasoning
- When market signals, competitive moves, or founder signals are identified
- When a meeting or call yields new information worth retaining
- Do NOT capture ephemeral task details, debugging steps, or implementation notes

### When to ingest documents (knowledge__ingest_document)
- Meeting transcripts pasted into conversation: ingest with doc_type "transcript"
- Research documents, PDFs, or web pages discussed: ingest for future search
- Email threads with strategic content: ingest key threads
- Always provide a descriptive title

### Tagging conventions
Use consistent tags for categorization:
- Themes: market-signals, competitive-landscape, product-analytics, data-infra, AI, regulation
- People: founders, portfolio, investors
- Activities: sourcing, strategy, M&A, thesis
- Verticals: fintech, gaming, ecommerce, climate, logistics

### When to search first (knowledge__search_knowledge)
- Before starting research on a topic: check what's already captured
- When context from prior conversations would help: search and surface it
- When the user references something discussed before: search rather than asking
