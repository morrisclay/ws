Show current workspace status. Run these checks and present a summary:

1. **Journal**: Read the last 10 entries from `.journal.jsonl` (if it exists). Summarize recent activity, open questions, and last decision.
2. **Git**: Run `git log --oneline -5` and `git status --short` to show recent commits and working tree state.
3. **Environment**: Check that `.env` exists and list which environment variables are set (names only, not values).
4. **Knowledge**: Search the knowledge layer for recent insights related to this project name.

Present as a concise dashboard — no lengthy explanations.
