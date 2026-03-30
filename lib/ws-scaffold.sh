#!/usr/bin/env bash
# ws-scaffold.sh — Project scaffolding (ws new)

source "$WS_SYSTEM/hooks/run-hooks.sh"

ws_new() {
  local name="" template="research"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template=*) template="${1#*=}"; shift ;;
      --template)   template="$2"; shift 2 ;;
      -t)           template="$2"; shift 2 ;;
      -*)           ws_die "Unknown flag: $1" ;;
      *)            name="$1"; shift ;;
    esac
  done

  [[ -z "$name" ]] && ws_die "Usage: ws new <name> [--template=<type>]"

  local project_dir="$WS_ROOT/$name"
  local template_dir="$WS_SYSTEM/templates/$template"

  [[ -d "$project_dir" ]] && ws_die "Project already exists: $name"
  [[ -d "$template_dir" ]] || ws_die "Unknown template: $template (available: $(ws_available_templates))"

  local today
  today=$(date +%Y-%m-%d)

  # Pre-scaffold hooks
  ws_run_hooks "pre-scaffold" "$name" "$template"

  echo ""
  echo "  Creating workspace: $name (template: $template)"
  echo ""

  # 1. Create directory
  mkdir -p "$project_dir"

  # 2. Initialize git repo
  git -C "$project_dir" init --quiet
  echo "  [+] git initialized"

  # 3. Copy and interpolate template files (skip manifest.toml — handled by flox init)
  for f in workspace.yaml CLAUDE.md gitignore; do
    if [[ -f "$template_dir/$f" ]]; then
      local dest
      case "$f" in
        workspace.yaml) dest="$project_dir/.workspace.yaml" ;;
        gitignore)      dest="$project_dir/.gitignore" ;;
        *)              dest="$project_dir/$f" ;;
      esac
      sed -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" "$template_dir/$f" > "$dest"
    fi
  done
  echo "  [+] template: $template applied"

  # 4. Initialize Flox environment
  flox init -d "$project_dir" --no-auto-setup 2>/dev/null
  # Overwrite manifest with our template version
  if [[ -f "$template_dir/manifest.toml" ]]; then
    sed -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" \
      "$template_dir/manifest.toml" > "$project_dir/.flox/env/manifest.toml"
  fi
  echo "  [+] flox environment initialized"

  # 5. Copy additional template files (if files/ directory exists)
  if [[ -d "$template_dir/files" ]]; then
    cp -R "$template_dir/files/." "$project_dir/"
    # Interpolate {{name}} and {{date}} in package.json if present
    if [[ -f "$project_dir/package.json" ]]; then
      sed -i '' -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" "$project_dir/package.json"
    fi
    echo "  [+] template files copied"
  fi

  # 6. Create template-specific directories (ensure structure)
  case "$template" in
    theme-research)
      mkdir -p "$project_dir"/{research,data,output}
      ;;
    deal-war-room)
      mkdir -p "$project_dir"/diligence/{team,market,product,financials}
      mkdir -p "$project_dir"/{materials,notes}
      ;;
    research)
      mkdir -p "$project_dir"/{research,data,output}
      ;;
    agent-dev)
      mkdir -p "$project_dir"/{src,tests}
      mkdir -p "$project_dir/.claude/skills"
      ;;
    agentic-email)
      mkdir -p "$project_dir"/voice/samples
      mkdir -p "$project_dir"/{drafts,triage}
      mkdir -p "$project_dir/.claude/skills/triage"
      ;;
    canvas)
      mkdir -p "$project_dir"/{src,server,bin}
      ;;
  esac
  # Add .gitkeep to empty dirs
  find "$project_dir" -type d -empty -not -path '*/.git/*' -not -path '*/.flox/*' \
    -exec touch {}/.gitkeep \;
  echo "  [+] directories created"

  # 7. Initial commit
  git -C "$project_dir" add -A
  git -C "$project_dir" commit -m "Initial workspace: $template template" --quiet
  echo "  [+] initial commit"

  # Post-scaffold hooks
  ws_run_hooks "post-scaffold" "$name" "$template"

  echo ""
  echo "  Workspace ready: ~/AI/$name"
  echo "  Launch with: ws $name"
  echo ""
}
