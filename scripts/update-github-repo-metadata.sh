#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_OWNER:-moye-source}"
REPO="${GITHUB_REPO:-moye-md}"
DESCRIPTION="${GITHUB_REPO_DESCRIPTION:-Native macOS Markdown editor built with SwiftUI and AppKit.}"
HOMEPAGE="${GITHUB_REPO_HOMEPAGE:-https://github.com/moye-source/moye-md/releases/latest}"
TOPICS_JSON='["macos","markdown","markdown-editor","swift","swiftui","appkit","native-macos","text-editor","writing","typora-alternative","open-source"]'

TOKEN_REF="${OP_GITHUB_TOKEN_REF:-op://Private/GitHub Personal Access Token/token}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  if ! command -v op >/dev/null 2>&1; then
    echo "Set GITHUB_TOKEN or install 1Password CLI: brew install 1password-cli" >&2
    exit 1
  fi
  GITHUB_TOKEN="$(op read "$TOKEN_REF")"
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "GitHub token is empty." >&2
  exit 1
fi

CURL_CONFIG="$(mktemp)"
cleanup() {
  rm -f "$CURL_CONFIG"
}
trap cleanup EXIT

chmod 600 "$CURL_CONFIG"
{
  printf 'header = "Accept: application/vnd.github+json"\n'
  printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN"
  printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
} >"$CURL_CONFIG"
unset GITHUB_TOKEN

api() {
  local method="$1"
  local path="$2"
  local data="$3"

  curl -fsSL \
    --config "$CURL_CONFIG" \
    -X "$method" \
    "https://api.github.com${path}" \
    -d "$data"
}

repo_payload="$(
  jq -n \
    --arg description "$DESCRIPTION" \
    --arg homepage "$HOMEPAGE" \
    '{description: $description, homepage: $homepage}'
)"

topics_payload="$(jq -n --argjson names "$TOPICS_JSON" '{names: $names}')"

api PATCH "/repos/$OWNER/$REPO" "$repo_payload" >/dev/null
api PUT "/repos/$OWNER/$REPO/topics" "$topics_payload" >/dev/null

curl -fsSL \
  --config "$CURL_CONFIG" \
  "https://api.github.com/repos/$OWNER/$REPO" |
  jq '{full_name, description, homepage, topics}'
