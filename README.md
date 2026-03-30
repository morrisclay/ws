# ws

A CLI for managing AI workspaces. Scaffolds projects with [Flox](https://flox.dev) environments, [1Password](https://developer.1password.com/docs/cli/) secrets, and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) context — then launches them in [cmux](https://cmux.dev).

## Install

```bash
# Clone into your AI workspace root
git clone https://github.com/morrisclay/ws.git ~/AI/.workspace

# Symlink the binary
ln -s ~/AI/.workspace/bin/ws ~/.local/bin/ws
```

Requires: `jq`, `ruby`, `flox`, `op` (1Password CLI), `cmux` (for launch/stop)

## Quick start

```bash
# Initialize any directory as a workspace
cd ~/projects/my-thing
ws init

# That's it. You get:
#   .workspace.yaml        config
#   CLAUDE.md              agent context + knowledge-layer instructions
#   .claude/settings.json  pre-approved permissions
#   .claude/commands/      /project:status, /project:handoff, /project:env-check
#   .env                   secrets auto-injected from 1Password
#   .flox/                 reproducible environment (auto-activated)
```

## Commands

```
ws init [--template=<type>]         Initialize current dir as workspace
ws new <name> [--template=<type>]   Scaffold a new project under ~/AI
ws <name>                           Launch (or focus) workspace in cmux
ws list                             List all workspaces
ws stop <name>                      Close a workspace
ws delete <name> [--force]          Delete permanently
ws edit <name>                      Edit .workspace.yaml
ws env [--inject]                   Sync .env from 1Password
ws journal <name> [options]         Session journal (findings, decisions, questions)
ws worktree <name> <branch>         Create git worktree (lockf-protected)
ws ingest <name>                    Fetch Linear data + web research
```

## Configuration

Edit `config.toml` (at `~/AI/.workspace/config.toml`) to configure ws:

```toml
[onepassword]
vault = "your-vault-name"
```

`ws env --inject` queries all items in the configured vault, generates `.env.template` with `op://` references, and injects `.env` automatically. To refresh after adding new secrets:

```bash
ws env --inject
```

## Templates

ws ships with a `default` template. You can add custom templates under `templates/` — each template is a directory containing any of:

- `CLAUDE.md` — agent context (interpolates `{{name}}` and `{{date}}`)
- `workspace.yaml` — workspace config
- `manifest.toml` — Flox manifest
- `gitignore` — gitignore entries
- `files/` — directory tree copied into the workspace

## Structure

```
.workspace/
  bin/ws              CLI entry point (symlinked to ~/.local/bin/ws)
  lib/                Core libraries (init, scaffold, launch, manage, journal)
  templates/          Workspace templates (default + custom)
  hooks/              Lifecycle hooks (pre/post scaffold, launch, stop)
  plugins/            Extensions (Linear ingest)
  config.toml         User configuration (1Password vault, etc.)
```
