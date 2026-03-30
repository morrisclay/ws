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

## Templates

| Template | Use case |
|---|---|
| `research` | General research |
| `theme-research` | VC theme deep-dives |
| `deal-war-room` | Company due diligence |
| `agent-dev` | AI agent development |
| `agentic-email` | AI-assisted email via Superhuman |
| `canvas` | Claude Code + TLDraw whiteboard |

```bash
ws init --template=agent-dev
ws new climate-tech --template=theme-research
```

## Secrets

`ws init` queries your 1Password `agent-harness` vault, generates `.env.template` with `op://` references for every item, and injects `.env` automatically. To refresh after adding new secrets:

```bash
ws env --inject
```

## Structure

```
.workspace/
  bin/ws              CLI entry point (symlinked to ~/.local/bin/ws)
  lib/                Core libraries (init, scaffold, launch, manage, journal)
  templates/          Workspace templates (_base + named templates)
  hooks/              Lifecycle hooks (pre/post scaffold, launch, stop)
  plugins/            Extensions (Linear ingest)
```
