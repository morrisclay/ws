#!/usr/bin/env bash
# ws-init.sh — In-place workspace initialization (ws init) and env hydration (ws env)

WS_REGISTRY="$WS_SYSTEM/registry.jsonl"
WS_OP_VAULT="agent-harness"

# --- ws init ---

ws_init() {
  local template="" force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template=*) template="${1#*=}"; shift ;;
      --template)   template="$2"; shift 2 ;;
      -t)           template="$2"; shift 2 ;;
      --force|-f)   force=true; shift ;;
      -*)           ws_die "Unknown flag: $1" ;;
      *)            ws_die "ws init takes no positional arguments (run it in the target directory)" ;;
    esac
  done

  local project_dir="$PWD"
  local name
  name=$(basename "$project_dir")
  local today
  today=$(date +%Y-%m-%d)
  local base_dir="$WS_SYSTEM/templates/_base"

  # Guard: already initialized
  if [[ -f "$project_dir/.workspace.yaml" && "$force" != true ]]; then
    echo "  Already initialized. Use --force to re-init."
    return 0
  fi

  # Guard: inside ~/AI (already a managed workspace)
  if [[ "$project_dir" == "$WS_ROOT/"* && "$project_dir" != "$WS_ROOT" && "$force" != true ]]; then
    if [[ -f "$project_dir/.workspace.yaml" ]]; then
      echo "  This directory is already a managed workspace under ~/AI/."
      echo "  Use --force to re-initialize."
      return 0
    fi
  fi

  # Validate template if specified
  if [[ -n "$template" ]]; then
    local template_dir="$WS_SYSTEM/templates/$template"
    [[ -d "$template_dir" ]] || ws_die "Unknown template: $template (available: $(ws_available_templates))"
  fi

  echo ""
  echo "  Initializing workspace: $name"
  [[ -n "$template" ]] && echo "  Template overlay: $template"
  echo ""

  # 1. Git init
  if [[ ! -d "$project_dir/.git" ]] && ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$project_dir" init --quiet
    echo "  [+] git initialized"
  else
    echo "  [~] git repo already exists"
  fi

  # 2. .workspace.yaml
  if [[ ! -f "$project_dir/.workspace.yaml" || "$force" == true ]]; then
    cat > "$project_dir/.workspace.yaml" <<EOF
name: "$name"
template: "${template:-generic}"
created: "$today"
standalone: true
EOF
    echo "  [+] .workspace.yaml"
  else
    echo "  [~] .workspace.yaml already exists"
  fi

  # 3. .gitignore (merge — append missing entries)
  _ws_merge_gitignore "$project_dir" "$base_dir/gitignore"
  echo "  [+] .gitignore"

  # 4. CLAUDE.md
  if [[ ! -f "$project_dir/CLAUDE.md" || "$force" == true ]]; then
    local claude_content
    claude_content=$(sed -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" "$base_dir/CLAUDE.md")

    # If a template overlay is specified and it has a CLAUDE.md, merge sections
    if [[ -n "$template" && -f "$WS_SYSTEM/templates/$template/CLAUDE.md" ]]; then
      local template_claude
      template_claude=$(sed -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" "$WS_SYSTEM/templates/$template/CLAUDE.md")
      # Use the template CLAUDE.md but append the knowledge section if it's missing
      if ! echo "$template_claude" | grep -q "Auto-Knowledge Capture"; then
        # Extract the knowledge section from the base
        local knowledge_section
        knowledge_section=$(sed -n '/^## Auto-Knowledge Capture/,$p' "$base_dir/CLAUDE.md")
        claude_content="$template_claude

$knowledge_section"
      else
        claude_content="$template_claude"
      fi
    fi

    echo "$claude_content" > "$project_dir/CLAUDE.md"
    echo "  [+] CLAUDE.md (with knowledge-layer instructions)"
  else
    echo "  [~] CLAUDE.md already exists (add knowledge-layer section manually if needed)"
  fi

  # 5. .claude/settings.json + .claude/commands/
  _ws_scaffold_claude_dir "$project_dir" "$force"

  # 6. .env.template + .env (dynamic from 1Password agent-harness vault)
  if [[ ! -f "$project_dir/.env.template" || "$force" == true ]]; then
    _ws_generate_env_template "$project_dir"
  else
    echo "  [~] .env.template already exists"
  fi

  # 7. Flox init
  if [[ ! -d "$project_dir/.flox" ]]; then
    flox init -d "$project_dir" --no-auto-setup 2>/dev/null
    # Apply base manifest
    local manifest_src="$base_dir/manifest.toml"
    if [[ -n "$template" && -f "$WS_SYSTEM/templates/$template/manifest.toml" ]]; then
      manifest_src="$WS_SYSTEM/templates/$template/manifest.toml"
    fi
    sed -e "s/{{name}}/$name/g" -e "s/{{date}}/$today/g" "$manifest_src" \
      > "$project_dir/.flox/env/manifest.toml"
    echo "  [+] flox environment initialized"
  else
    echo "  [~] flox environment already exists"
  fi

  # 8. Template overlay (directories + files)
  if [[ -n "$template" ]]; then
    _ws_apply_template_dirs "$project_dir" "$template"
    # Copy template files/ if present
    if [[ -d "$WS_SYSTEM/templates/$template/files" ]]; then
      cp -Rn "$WS_SYSTEM/templates/$template/files/." "$project_dir/" 2>/dev/null || true
      echo "  [+] template files copied"
    fi
  fi

  # 9. Register
  _ws_register "$project_dir" "$name" "${template:-generic}"

  echo ""
  echo "  Workspace ready: $project_dir"
  echo ""

  # Activate flox environment (exec replaces this process with activated shell)
  if [[ -d "$project_dir/.flox" ]]; then
    echo "  Activating flox environment..."
    echo ""
    exec flox activate -d "$project_dir"
  fi
}

# --- ws env ---

ws_env() {
  local inject=false refresh=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --inject|-i)  inject=true; shift ;;
      --refresh|-r) refresh=true; shift ;;
      -*)           ws_die "Unknown flag: $1. Usage: ws env [--inject|--refresh]" ;;
      *)            ws_die "Usage: ws env [--inject|--refresh]" ;;
    esac
  done

  # Find workspace root by walking up
  local ws_root
  ws_root=$(_ws_find_root)
  [[ -n "$ws_root" ]] || ws_die "Not inside a workspace (no .workspace.yaml found)"

  local name
  name=$(basename "$ws_root")

  if [[ "$refresh" == true ]]; then
    # Regenerate .env.template from vault + inject
    _ws_generate_env_template "$ws_root"
    return
  fi

  if [[ "$inject" == true ]]; then
    # Inject mode — regenerate template from vault, then inject
    _ws_generate_env_template "$ws_root"
    return
  fi

  # Status mode
  echo ""
  echo "  Workspace: $name ($ws_root)"
  echo "  Vault: $WS_OP_VAULT"
  echo ""

  # Show what's in the vault right now
  if command -v op >/dev/null 2>&1; then
    local vault_items
    vault_items=$(op item list --vault "$WS_OP_VAULT" --format=json 2>/dev/null | jq -r '.[].title' 2>/dev/null || true)
    if [[ -n "$vault_items" ]]; then
      local item_count
      item_count=$(echo "$vault_items" | wc -l | tr -d ' ')
      echo "  1Password ($WS_OP_VAULT): $item_count secrets"
      echo "$vault_items" | while IFS= read -r title; do
        local var_name
        var_name=$(_ws_title_to_var "$title")
        printf "    %-24s %s\n" "$var_name" "op://$WS_OP_VAULT/$title/credential"
      done
    else
      echo "  1Password ($WS_OP_VAULT): no items found"
    fi
  else
    echo "  1Password CLI (op): not installed"
  fi

  echo ""

  if [[ -f "$ws_root/.env" ]]; then
    local env_count
    env_count=$(grep -cE '^[A-Z_]+=.' "$ws_root/.env" 2>/dev/null || echo "0")
    echo "  .env: found ($env_count vars set)"
  else
    echo "  .env: not found"
  fi

  if [[ -f "$ws_root/.env.template" ]]; then
    echo "  .env.template: found"
  else
    echo "  .env.template: not found"
  fi

  echo ""
  echo "  Run 'ws env --inject' to sync secrets from 1Password."
  echo ""
}

# --- Helpers ---

_ws_title_to_var() {
  # Convert 1Password item title to UPPER_SNAKE_CASE env var name
  # "Brave API Key" -> "BRAVE_API_KEY"
  # "Openrouter" -> "OPENROUTER"
  echo "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

_ws_generate_env_template() {
  local project_dir="$1"

  command -v op >/dev/null 2>&1 || {
    echo "  [!] 1Password CLI (op) not found — skipping .env generation"
    return 0
  }

  # Query agent-harness vault for all items
  local items_json
  items_json=$(op item list --vault "$WS_OP_VAULT" --format=json 2>/dev/null) || {
    echo "  [!] Could not query 1Password vault '$WS_OP_VAULT' — skipping .env generation"
    return 0
  }

  local titles
  titles=$(echo "$items_json" | jq -r '.[].title' 2>/dev/null)

  if [[ -z "$titles" ]]; then
    echo "  [!] No items found in vault '$WS_OP_VAULT'"
    return 0
  fi

  local item_count
  item_count=$(echo "$titles" | wc -l | tr -d ' ')

  # Build .env.template
  {
    echo "# Auto-generated from 1Password vault: $WS_OP_VAULT"
    echo "# Regenerate with: ws env --inject"
    echo "# $(date +%Y-%m-%d)"
    echo ""
    echo "$titles" | while IFS= read -r title; do
      local var_name
      var_name=$(_ws_title_to_var "$title")
      echo "$var_name={{ op://$WS_OP_VAULT/$title/credential }}"
    done
  } > "$project_dir/.env.template"

  echo "  [+] .env.template ($item_count secrets from $WS_OP_VAULT)"

  # Auto-inject .env
  if op inject -i "$project_dir/.env.template" -o "$project_dir/.env" 2>/dev/null; then
    echo "  [+] .env hydrated from 1Password"
  else
    echo "  [!] op inject failed — .env.template created but .env not populated"
    echo "      Check: op item list --vault $WS_OP_VAULT"
  fi
}

_ws_scaffold_claude_dir() {
  local project_dir="$1" force="$2"
  local base_dir="$WS_SYSTEM/templates/_base"

  # .claude/settings.json
  mkdir -p "$project_dir/.claude"
  if [[ ! -f "$project_dir/.claude/settings.json" || "$force" == true ]]; then
    cp "$base_dir/claude-settings.json" "$project_dir/.claude/settings.json"
  fi

  # .claude/commands/ — copy all standard commands
  mkdir -p "$project_dir/.claude/commands"
  local copied=0
  for cmd_file in "$base_dir"/claude-commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    local cmd_name
    cmd_name=$(basename "$cmd_file")
    if [[ ! -f "$project_dir/.claude/commands/$cmd_name" || "$force" == true ]]; then
      cp "$cmd_file" "$project_dir/.claude/commands/$cmd_name"
      copied=$((copied + 1))
    fi
  done

  echo "  [+] .claude/ (settings + $copied commands: status, handoff, env-check)"
}

_ws_find_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.workspace.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

_ws_merge_gitignore() {
  local project_dir="$1" template_gitignore="$2"

  if [[ ! -f "$project_dir/.gitignore" ]]; then
    cp "$template_gitignore" "$project_dir/.gitignore"
    return
  fi

  # Append missing entries
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -qxF "$line" "$project_dir/.gitignore" 2>/dev/null; then
      echo "$line" >> "$project_dir/.gitignore"
    fi
  done < "$template_gitignore"
}

_ws_register() {
  local abs_path="$1" name="$2" template="$3"
  local today
  today=$(date +%Y-%m-%d)

  # Don't register workspaces under ~/AI (they're already discoverable)
  if [[ "$abs_path" == "$WS_ROOT/"* && "$abs_path" != "$WS_ROOT" ]]; then
    return 0
  fi

  # Create registry if it doesn't exist
  touch "$WS_REGISTRY"

  # Remove existing entry for this path (dedup)
  if grep -q "\"path\":\"$abs_path\"" "$WS_REGISTRY" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    grep -v "\"path\":\"$abs_path\"" "$WS_REGISTRY" > "$tmp" || true
    mv "$tmp" "$WS_REGISTRY"
  fi

  # Append new entry
  printf '{"path":"%s","name":"%s","template":"%s","created":"%s"}\n' \
    "$abs_path" "$name" "$template" "$today" >> "$WS_REGISTRY"
}

_ws_apply_template_dirs() {
  local project_dir="$1" template="$2"

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
  find "$project_dir" -type d -empty \
    -not -path '*/.git/*' -not -path '*/.flox/*' \
    -exec touch {}/.gitkeep \; 2>/dev/null || true

  echo "  [+] template directories created"
}
