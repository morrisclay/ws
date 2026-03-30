Write a session handoff for the next session. This is MANDATORY before ending work.

1. **Summarize** what was accomplished this session (2-3 bullet points).
2. **Log** a journal `note` entry with the summary:
   ```bash
   printf '{"ts":"%s","type":"note","text":"Session handoff: %s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "SUMMARY" >> .journal.jsonl
   ```
3. **Log** any unresolved questions as `open_question` entries.
4. **Capture** any non-obvious strategic insights to the knowledge layer via `knowledge__capture_insight`.
5. **State** what the next session should pick up on (1-2 sentences).

Be concise. The next session will read the journal to resume.
