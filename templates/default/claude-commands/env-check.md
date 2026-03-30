Verify the workspace environment is correctly configured.

Check each of the following and report pass/fail:

1. **`.env` exists** and is non-empty
2. **`.env` is gitignored** — verify `.env` appears in `.gitignore`
3. **`.env.template` exists** — the 1Password reference file
4. **Environment variables loaded** — run `env | grep -E '^[A-Z_]+=' | cut -d= -f1 | sort` and compare against what's in `.env.template`
5. **Flox active** — check if `$FLOX_ENV` is set
6. **Git repo** — verify `.git/` exists and show current branch
7. **Journal** — check if `.journal.jsonl` exists, show entry count if so

If any checks fail, suggest the fix command (e.g., `ws env --inject`, `flox activate`).
