#!/usr/bin/env bash
set -euo pipefail

# linear-fetch.sh — Download all data from a Linear project into structured local files.
# Requires: curl, jq, LINEAR_API_KEY env var
# Usage: linear-fetch.sh --project-id <UUID> [--output-dir <path>]

LINEAR_ENDPOINT="https://api.linear.app/graphql"

# --- Args ---
PROJECT_ID=""
OUTPUT_DIR="data/linear"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)  PROJECT_ID="$2"; shift 2 ;;
    --project-id=*) PROJECT_ID="${1#*=}"; shift ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --output-dir=*) OUTPUT_DIR="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: linear-fetch.sh --project-id <UUID> [--output-dir <path>]"
      echo "  Downloads all issues, documents, and updates from a Linear project."
      echo "  Requires LINEAR_API_KEY environment variable."
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" ]] && { echo "error: --project-id required" >&2; exit 1; }
[[ -z "${LINEAR_API_KEY:-}" ]] && { echo "error: LINEAR_API_KEY not set. Add it to .env or export it." >&2; exit 1; }
command -v curl >/dev/null || { echo "error: curl required" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq required" >&2; exit 1; }

# --- GraphQL helper ---
linear_query() {
  local query="$1" variables="${2:-null}"
  local payload
  payload=$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')

  local response http_code
  response=$(curl -s -w "\n%{http_code}" -X POST "$LINEAR_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "$payload")

  http_code=$(echo "$response" | tail -1)
  response=$(echo "$response" | sed '$d')

  if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    echo "error: authentication failed (HTTP $http_code). Check LINEAR_API_KEY." >&2
    return 1
  fi
  if [[ "$http_code" -ge 500 ]]; then
    echo "error: Linear API error (HTTP $http_code)" >&2
    return 3
  fi

  local api_error
  api_error=$(echo "$response" | jq -r '.errors[0].message // empty' 2>/dev/null)
  if [[ -n "$api_error" ]]; then
    echo "error: Linear API: $api_error" >&2
    return 2
  fi

  echo "$response" | jq '.data'
}

# --- Setup output dirs ---
mkdir -p "$OUTPUT_DIR/issues" "$OUTPUT_DIR/documents" "$OUTPUT_DIR/updates"

echo "Fetching Linear project: $PROJECT_ID" >&2

# --- 1. Project metadata ---
echo "  [1/4] Project metadata..." >&2

PROJECT_QUERY='query ProjectDetails($id: String!) {
  project(id: $id) {
    id name description url state
    lead { name displayName }
    startDate targetDate
    teams { nodes { id name key } }
    members { nodes { id name displayName } }
  }
}'

project_data=$(linear_query "$PROJECT_QUERY" "$(jq -n --arg id "$PROJECT_ID" '{id: $id}')")

if [[ -z "$project_data" || "$project_data" == "null" ]]; then
  echo "error: project $PROJECT_ID not found" >&2
  exit 2
fi

project_name=$(echo "$project_data" | jq -r '.project.name // "Unknown"')
echo "$project_data" | jq '.project' > "$OUTPUT_DIR/project.json"

# Generate project.md
{
  echo "# $project_name"
  echo ""
  echo "**State**: $(echo "$project_data" | jq -r '.project.state // "unknown"')"
  local_lead=$(echo "$project_data" | jq -r '.project.lead.displayName // .project.lead.name // "unassigned"')
  echo "**Lead**: $local_lead"
  echo "**URL**: $(echo "$project_data" | jq -r '.project.url // ""')"
  start=$(echo "$project_data" | jq -r '.project.startDate // "not set"')
  target=$(echo "$project_data" | jq -r '.project.targetDate // "not set"')
  echo "**Timeline**: $start to $target"
  echo ""
  desc=$(echo "$project_data" | jq -r '.project.description // ""')
  if [[ -n "$desc" ]]; then
    echo "## Description"
    echo ""
    echo "$desc"
    echo ""
  fi
  echo "## Teams"
  echo "$project_data" | jq -r '.project.teams.nodes[] | "- \(.name) (\(.key))"' 2>/dev/null || echo "- (none)"
  echo ""
  echo "## Members"
  echo "$project_data" | jq -r '.project.members.nodes[] | "- \(.displayName // .name)"' 2>/dev/null || echo "- (none)"
} > "$OUTPUT_DIR/project.md"

echo "  -> $project_name" >&2

# --- 2. Issues (paginated) ---
echo "  [2/4] Issues..." >&2

ISSUES_QUERY='query ProjectIssues($projectId: String!, $first: Int, $after: String) {
  project(id: $projectId) {
    issues(first: $first, after: $after, orderBy: updatedAt) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id identifier title url description priority
        createdAt updatedAt
        state { name type color }
        assignee { name displayName }
        team { name key }
        labels { nodes { id name color } }
        comments(first: 50, orderBy: createdAt) {
          nodes { id body createdAt user { name displayName } }
        }
        parent { id identifier title url state { name type } }
        children { nodes { id identifier title url state { name type } assignee { name displayName } } }
        relations { nodes { type relatedIssue { id identifier title url state { name type } } } }
      }
    }
  }
}'

all_issues="[]"
cursor=""
has_next="true"
page=0

while [[ "$has_next" == "true" ]]; do
  page=$((page + 1))
  local_vars=$(jq -n --arg pid "$PROJECT_ID" --argjson first 100 '{projectId: $pid, first: $first}')
  if [[ -n "$cursor" ]]; then
    local_vars=$(echo "$local_vars" | jq --arg after "$cursor" '. + {after: $after}')
  fi

  result=$(linear_query "$ISSUES_QUERY" "$local_vars")
  page_issues=$(echo "$result" | jq '.project.issues.nodes // []')
  page_count=$(echo "$page_issues" | jq 'length')
  all_issues=$(echo "$all_issues" "$page_issues" | jq -s '.[0] + .[1]')

  has_next=$(echo "$result" | jq -r '.project.issues.pageInfo.hasNextPage // false')
  cursor=$(echo "$result" | jq -r '.project.issues.pageInfo.endCursor // empty')

  echo "    page $page: $page_count issues" >&2
done

total_issues=$(echo "$all_issues" | jq 'length')
echo "  -> $total_issues issues total" >&2

# Write issues index
echo "$all_issues" | jq '[.[] | {id, identifier, title, state: .state.name, priority, assignee: (.assignee.displayName // .assignee.name // "unassigned"), team: .team.key, updated: .updatedAt}]' > "$OUTPUT_DIR/issues/index.json"

# Write issues index.md
{
  echo "# Issues ($total_issues)"
  echo ""
  echo "| ID | Title | State | Priority | Assignee |"
  echo "|---|---|---|---|---|"
  echo "$all_issues" | jq -r '.[] | "| \(.identifier) | \(.title) | \(.state.name) | \(.priority) | \(.assignee.displayName // .assignee.name // "—") |"'
} > "$OUTPUT_DIR/issues/index.md"

# Write individual issue files
echo "$all_issues" | jq -c '.[]' | while IFS= read -r issue; do
  ident=$(echo "$issue" | jq -r '.identifier')
  safe_ident=$(echo "$ident" | tr '/' '-')

  # Raw JSON
  echo "$issue" > "$OUTPUT_DIR/issues/${safe_ident}.json"

  # Markdown
  {
    title=$(echo "$issue" | jq -r '.title')
    state=$(echo "$issue" | jq -r '.state.name')
    priority=$(echo "$issue" | jq -r '.priority')
    assignee=$(echo "$issue" | jq -r '.assignee.displayName // .assignee.name // "unassigned"')
    team=$(echo "$issue" | jq -r '.team.name // ""')
    team_key=$(echo "$issue" | jq -r '.team.key // ""')
    url=$(echo "$issue" | jq -r '.url // ""')
    updated=$(echo "$issue" | jq -r '.updatedAt // ""' | cut -c1-10)

    # Priority label
    case "$priority" in
      0) pri_label="No priority" ;;
      1) pri_label="Urgent" ;;
      2) pri_label="High" ;;
      3) pri_label="Medium" ;;
      4) pri_label="Low" ;;
      *) pri_label="$priority" ;;
    esac

    echo "# $ident: $title"
    echo ""
    echo "**State**: $state | **Priority**: $pri_label | **Assignee**: $assignee"

    labels=$(echo "$issue" | jq -r '[.labels.nodes[].name] | join(", ")' 2>/dev/null)
    [[ -n "$labels" ]] && echo "**Labels**: $labels"

    echo "**Team**: $team ($team_key) | **Updated**: $updated"
    [[ -n "$url" ]] && echo "**URL**: $url"
    echo ""

    desc=$(echo "$issue" | jq -r '.description // ""')
    if [[ -n "$desc" ]]; then
      echo "## Description"
      echo ""
      echo "$desc"
      echo ""
    fi

    # Comments
    comment_count=$(echo "$issue" | jq '.comments.nodes | length')
    if [[ "$comment_count" -gt 0 ]]; then
      echo "## Comments ($comment_count)"
      echo ""
      echo "$issue" | jq -c '.comments.nodes[]' | while IFS= read -r comment; do
        cuser=$(echo "$comment" | jq -r '.user.displayName // .user.name // "Unknown"')
        cdate=$(echo "$comment" | jq -r '.createdAt // ""' | cut -c1-10)
        cbody=$(echo "$comment" | jq -r '.body // ""')
        echo "### $cuser — $cdate"
        echo ""
        echo "$cbody"
        echo ""
      done
    fi

    # Children
    child_count=$(echo "$issue" | jq '.children.nodes | length')
    if [[ "$child_count" -gt 0 ]]; then
      echo "## Sub-issues ($child_count)"
      echo ""
      echo "$issue" | jq -r '.children.nodes[] | "- \(.identifier): \(.title) (\(.state.name)) — \(.assignee.displayName // .assignee.name // "unassigned")"' 2>/dev/null
      echo ""
    fi

    # Parent
    parent=$(echo "$issue" | jq -r '.parent // empty')
    if [[ -n "$parent" && "$parent" != "null" ]]; then
      pident=$(echo "$issue" | jq -r '.parent.identifier')
      ptitle=$(echo "$issue" | jq -r '.parent.title')
      echo "**Parent**: $pident — $ptitle"
      echo ""
    fi

    # Relations
    rel_count=$(echo "$issue" | jq '.relations.nodes | length')
    if [[ "$rel_count" -gt 0 ]]; then
      echo "## Relations"
      echo ""
      echo "$issue" | jq -r '.relations.nodes[] | "- \(.type): \(.relatedIssue.identifier) — \(.relatedIssue.title) (\(.relatedIssue.state.name))"' 2>/dev/null
      echo ""
    fi
  } > "$OUTPUT_DIR/issues/${safe_ident}.md"
done

# --- 3. Documents ---
echo "  [3/4] Documents..." >&2

DOCS_QUERY='query ProjectDocuments($projectId: String!, $first: Int) {
  project(id: $projectId) {
    documents(first: $first, orderBy: updatedAt) {
      nodes { id title url content createdAt updatedAt creator { name displayName } }
    }
  }
}'

docs_data=$(linear_query "$DOCS_QUERY" "$(jq -n --arg pid "$PROJECT_ID" --argjson first 100 '{projectId: $pid, first: $first}')")
all_docs=$(echo "$docs_data" | jq '.project.documents.nodes // []')
total_docs=$(echo "$all_docs" | jq 'length')

echo "  -> $total_docs documents" >&2

# Write docs index
echo "$all_docs" | jq '[.[] | {id, title, url, creator: (.creator.displayName // .creator.name // "unknown"), updated: .updatedAt}]' > "$OUTPUT_DIR/documents/index.json"

# Write individual documents
echo "$all_docs" | jq -c '.[]' | while IFS= read -r doc; do
  doc_title=$(echo "$doc" | jq -r '.title // "Untitled"')
  doc_id=$(echo "$doc" | jq -r '.id')
  # Create safe filename from title
  safe_name=$(echo "$doc_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  [[ -z "$safe_name" ]] && safe_name="$doc_id"

  {
    echo "# $doc_title"
    echo ""
    creator=$(echo "$doc" | jq -r '.creator.displayName // .creator.name // "unknown"')
    updated=$(echo "$doc" | jq -r '.updatedAt // ""' | cut -c1-10)
    url=$(echo "$doc" | jq -r '.url // ""')
    echo "**Author**: $creator | **Updated**: $updated"
    [[ -n "$url" ]] && echo "**URL**: $url"
    echo ""
    echo "---"
    echo ""
    echo "$doc" | jq -r '.content // ""'
  } > "$OUTPUT_DIR/documents/${safe_name}.md"
done

# --- 4. Project updates ---
echo "  [4/4] Project updates..." >&2

UPDATES_QUERY='query ProjectUpdates($projectId: String!, $first: Int) {
  project(id: $projectId) {
    projectUpdates(first: $first, orderBy: createdAt) {
      nodes { id body health createdAt user { name displayName } }
    }
  }
}'

updates_data=$(linear_query "$UPDATES_QUERY" "$(jq -n --arg pid "$PROJECT_ID" --argjson first 50 '{projectId: $pid, first: $first}')")
all_updates=$(echo "$updates_data" | jq '.project.projectUpdates.nodes // []')
total_updates=$(echo "$all_updates" | jq 'length')

echo "  -> $total_updates updates" >&2

echo "$all_updates" > "$OUTPUT_DIR/updates/index.json"

# Write updates as single markdown file
if [[ "$total_updates" -gt 0 ]]; then
  {
    echo "# Project Updates"
    echo ""
    echo "$all_updates" | jq -c '.[]' | while IFS= read -r update; do
      uuser=$(echo "$update" | jq -r '.user.displayName // .user.name // "Unknown"')
      udate=$(echo "$update" | jq -r '.createdAt // ""' | cut -c1-10)
      uhealth=$(echo "$update" | jq -r '.health // "unknown"')
      ubody=$(echo "$update" | jq -r '.body // ""')
      echo "## $udate — $uuser (Health: $uhealth)"
      echo ""
      echo "$ubody"
      echo ""
      echo "---"
      echo ""
    done
  } > "$OUTPUT_DIR/updates/updates.md"
fi

# --- Summary ---
echo "" >&2
echo "Linear fetch complete:" >&2
echo "  Project: $project_name" >&2
echo "  Issues:  $total_issues" >&2
echo "  Docs:    $total_docs" >&2
echo "  Updates: $total_updates" >&2
echo "  Output:  $OUTPUT_DIR" >&2

# Output manifest to stdout (for programmatic use)
jq -n \
  --arg project_id "$PROJECT_ID" \
  --arg project_name "$project_name" \
  --arg fetched_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson issues "$total_issues" \
  --argjson documents "$total_docs" \
  --argjson updates "$total_updates" \
  --arg output_dir "$OUTPUT_DIR" \
  '{
    project_id: $project_id,
    project_name: $project_name,
    fetched_at: $fetched_at,
    issues_count: $issues,
    documents_count: $documents,
    updates_count: $updates,
    output_dir: $output_dir,
    status: "complete"
  }'
