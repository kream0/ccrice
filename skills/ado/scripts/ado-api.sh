#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------
# ado-api.sh  -  Azure DevOps REST API helper
#
# Works in WSL (bash) and from PowerShell (bash ./ado-api.sh ... or wsl ...).
# Requires: curl, jq (optional, for pretty output)
#
# Configuration (env vars or .ado-config file):
#   ADO_PAT       - Personal Access Token (required)
#   ADO_ORG       - Organization name      (required)
#   ADO_PROJECT   - Project name           (required)
#   ADO_API_VER   - API version            (default: 7.0)
#
# The --repo flag is REQUIRED on all PR commands. No default repo is used,
# so the caller must always specify which repository to target.
# -----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Config loading ----------

load_config() {
    local cfg="${ADO_CONFIG_FILE:-${SCRIPT_DIR}/.ado-config}"
    [[ -f "$cfg" ]] && source "$cfg"
    ADO_API_VER="${ADO_API_VER:-7.0}"
}

require_vars() {
    local missing=()
    for v in "$@"; do
        [[ -z "${!v:-}" ]] && missing+=("$v")
    done
    if (( ${#missing[@]} )); then
        die "Missing required config: ${missing[*]}"
    fi
}

# ---------- Helpers ----------

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ":: $*" >&2; }

fmt() {
    if command -v jq &>/dev/null; then
        jq .
    else
        cat
    fi
}

ado_request() {
    local method="$1"
    local url="$2"
    local body="${3:-}"

    local -a curl_args=(
        -s -S --fail-with-body
        -u ":${ADO_PAT}"
        -H "Content-Type: application/json"
        -X "$method"
    )

    [[ -n "$body" ]] && curl_args+=(-d "$body")

    local http_response
    if ! http_response=$(curl "${curl_args[@]}" "$url" 2>&1); then
        die "Request failed: $method $url -- $http_response"
    fi
    echo "$http_response"
}

base_url() { echo "https://dev.azure.com/${ADO_ORG}/${ADO_PROJECT}"; }

repo_url() {
    local repo="$1"
    [[ -z "$repo" ]] && die "Missing --repo <name>. The repository must be specified explicitly."
    echo "$(base_url)/_apis/git/repositories/${repo}"
}

# ---------- Work Items ----------

cmd_work_item() {
    local id="${1:?Usage: ado-api.sh work-item <id>}"
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local url
    url="$(base_url)/_apis/wit/workitems/${id}?\$expand=relations&api-version=${ADO_API_VER}"
    ado_request GET "$url" | fmt
}

cmd_work_items() {
    local wit_type="${1:?Usage: ado-api.sh work-items <Task|Bug|User Story> [--state <state>] [--top N]}"
    shift

    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local state="" top="50"
    while (( $# )); do
        case "$1" in
            --state) state="$2"; shift 2 ;;
            --top)   top="$2";   shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local wiql="SELECT [System.Id],[System.Title],[System.State],[System.AssignedTo] \
FROM WorkItems \
WHERE [System.TeamProject] = '${ADO_PROJECT}' \
AND [System.WorkItemType] = '${wit_type}'"

    [[ -n "$state" ]] && wiql+=" AND [System.State] = '${state}'"
    wiql+=" ORDER BY [System.ChangedDate] DESC"

    local body
    body=$(printf '{"query":"%s","$top":%s}' "$wiql" "$top")

    local url
    url="$(base_url)/_apis/wit/wiql?api-version=${ADO_API_VER}"
    ado_request POST "$url" "$body" | fmt
}

# ---------- Pull Requests ----------

cmd_prs() {
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local repo="" status="active" top="25" creator=""
    while (( $# )); do
        case "$1" in
            --repo)    repo="$2";    shift 2 ;;
            --status)  status="$2";  shift 2 ;;
            --top)     top="$2";     shift 2 ;;
            --creator) creator="$2"; shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local url
    url="$(repo_url "$repo")/pullrequests?searchCriteria.status=${status}&\$top=${top}&api-version=${ADO_API_VER}"
    [[ -n "$creator" ]] && url+="&searchCriteria.creatorId=${creator}"

    ado_request GET "$url" | fmt
}

cmd_pr_get() {
    local pr_id="${1:?Usage: ado-api.sh pr-get <pr-id> --repo <name>}"
    shift
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local repo=""
    while (( $# )); do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local url
    url="$(repo_url "$repo")/pullrequests/${pr_id}?api-version=${ADO_API_VER}"
    ado_request GET "$url" | fmt
}

cmd_pr_create() {
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local source="" target="" title="" description="" repo="" reviewers="" draft="false"
    while (( $# )); do
        case "$1" in
            --source)      source="$2";      shift 2 ;;
            --target)      target="$2";      shift 2 ;;
            --title)       title="$2";       shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --repo)        repo="$2";        shift 2 ;;
            --reviewers)   reviewers="$2";   shift 2 ;;
            --draft)       draft="true";     shift   ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    [[ -z "$source" ]] && die "Missing --source <branch>"
    [[ -z "$target" ]] && die "Missing --target <branch>"
    [[ -z "$title"  ]] && die "Missing --title <title>"

    [[ "$source" != refs/* ]] && source="refs/heads/${source}"
    [[ "$target" != refs/* ]] && target="refs/heads/${target}"

    local body
    if command -v jq &>/dev/null; then
        body=$(jq -n \
            --arg src "$source" \
            --arg tgt "$target" \
            --arg ttl "$title" \
            --arg desc "$description" \
            --argjson draft "$draft" \
            '{sourceRefName:$src, targetRefName:$tgt, title:$ttl, description:$desc, isDraft:$draft}')
    else
        local desc_escaped title_escaped
        desc_escaped=$(printf '%s' "$description" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        title_escaped=$(printf '%s' "$title" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        body="{\"sourceRefName\":\"${source}\",\"targetRefName\":\"${target}\",\"title\":${title_escaped},\"description\":${desc_escaped},\"isDraft\":${draft}}"
    fi

    if [[ -n "$reviewers" ]]; then
        local rev_array="["
        local first=true
        IFS=',' read -ra rev_ids <<< "$reviewers"
        for rid in "${rev_ids[@]}"; do
            $first || rev_array+=","
            rev_array+="{\"id\":\"$(echo -n "$rid" | xargs)\"}"
            first=false
        done
        rev_array+="]"
        if command -v jq &>/dev/null; then
            body=$(echo "$body" | jq --argjson r "$rev_array" '. + {reviewers: $r}')
        fi
    fi

    local url
    url="$(repo_url "$repo")/pullrequests?api-version=${ADO_API_VER}"
    ado_request POST "$url" "$body" | fmt
}

# ---------- PR Comments / Threads ----------

cmd_pr_comments() {
    local pr_id="${1:?Usage: ado-api.sh pr-comments <pr-id> --repo <name>}"
    shift
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local repo=""
    while (( $# )); do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local url
    url="$(repo_url "$repo")/pullrequests/${pr_id}/threads?api-version=${ADO_API_VER}"
    ado_request GET "$url" | fmt
}

cmd_pr_reply() {
    local pr_id="${1:?Usage: ado-api.sh pr-reply <pr-id> <thread-id> <content> --repo <name>}"
    local thread_id="${2:?Missing <thread-id>}"
    local content="${3:?Missing <content>}"
    shift 3
    require_vars ADO_PAT ADO_ORG ADO_PROJECT

    local repo=""
    while (( $# )); do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    local body
    if command -v jq &>/dev/null; then
        body=$(jq -n --arg c "$content" '{content:$c, commentType:1}')
    else
        local content_escaped
        content_escaped=$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        body="{\"content\":${content_escaped},\"commentType\":1}"
    fi

    local url
    url="$(repo_url "$repo")/pullrequests/${pr_id}/threads/${thread_id}/comments?api-version=${ADO_API_VER}"
    ado_request POST "$url" "$body" | fmt
}

# ---------- CLI router ----------

usage() {
    cat <<'EOF'
Azure DevOps REST API helper

Usage: ado-api.sh <command> [args]

Commands:
  work-item   <id>                                     Fetch a single work item
  work-items  <Task|Bug|User Story> [--state S] [--top N]
                                                        Query work items by type
  prs         --repo R [--status S] [--top N] [--creator C]
                                                        List pull requests
  pr-get      <pr-id> --repo R                         Fetch a single PR
  pr-create   --repo R --source <branch> --target <branch> --title <title>
              [--description D] [--reviewers id1,id2] [--draft]
                                                        Create a pull request
  pr-comments <pr-id> --repo R                         List PR comment threads
  pr-reply    <pr-id> <thread-id> <content> --repo R   Reply to a comment thread

Config (env vars or .ado-config):
  ADO_PAT       Personal Access Token     (required)
  ADO_ORG       Organization name          (required)
  ADO_PROJECT   Project name               (required)
  ADO_API_VER   API version (default: 7.0) (optional)

Note: --repo is required on all PR commands (no default).
EOF
    exit 0
}

main() {
    load_config

    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        work-item)    cmd_work_item "$@" ;;
        work-items)   cmd_work_items "$@" ;;
        prs)          cmd_prs "$@" ;;
        pr-get)       cmd_pr_get "$@" ;;
        pr-create)    cmd_pr_create "$@" ;;
        pr-comments)  cmd_pr_comments "$@" ;;
        pr-reply)     cmd_pr_reply "$@" ;;
        help|--help|-h) usage ;;
        *) die "Unknown command: $cmd. Run with --help for usage." ;;
    esac
}

main "$@"
