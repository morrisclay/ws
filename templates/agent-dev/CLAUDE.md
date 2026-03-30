# {{name}} — Agent Development

## Purpose
Development workspace for building AI agents. Contains source code, tests, and tooling.

## Structure
- `src/` — Agent source code
- `tests/` — Test suites
- `.claude/skills/` — Claude Code agent skills

## Workflow
1. Define agent behavior and capabilities
2. Implement in `src/`
3. Write tests in `tests/`
4. Iterate with Claude Code in the workspace
5. Test end-to-end before deploying

## Journal

This workspace uses `.journal.jsonl` for continuity across sessions. On startup, read the last 20 entries to understand where work left off.

Log important events during your session:
```bash
ws journal {{name}} --finding "Tool schema validated against MCP spec"
ws journal {{name}} --question "Should we use streaming or batch for responses?"
ws journal {{name}} --decision "Using TypeScript + Zod for schema validation"
ws journal {{name}} --note "Tests passing, ready for integration testing"
```

Entry types: `finding`, `open_question`, `decision`, `note`, `stage_change`

## Conventions
- Write tests for all agent behaviors
- Keep agent definitions modular
- Document MCP tool schemas
- Use TypeScript where possible
