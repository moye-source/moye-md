#!/usr/bin/env bash
set -euo pipefail

VAULT="${OP_VAULT:-Private}"
ITEM_TITLE="${OP_GITHUB_TOKEN_ITEM:-GitHub Personal Access Token}"
FIELD_NAME="${OP_GITHUB_TOKEN_FIELD:-token}"
TAGS="github,moye-source,token"

if ! command -v op >/dev/null 2>&1; then
  echo "1Password CLI is required. Install it with: brew install 1password-cli" >&2
  exit 1
fi

printf "Paste GitHub token for %s, then press Enter: " "$ITEM_TITLE" >&2
IFS= read -rs TOKEN
printf "\n" >&2

if [[ -z "$TOKEN" ]]; then
  echo "Token is empty; nothing was saved." >&2
  exit 1
fi

TOKEN_FILE="$(mktemp)"
TEMPLATE_FILE="$(mktemp)"
PAYLOAD_FILE="$(mktemp)"

cleanup() {
  rm -f "$TOKEN_FILE" "$TEMPLATE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

chmod 600 "$TOKEN_FILE" "$TEMPLATE_FILE" "$PAYLOAD_FILE"
printf "%s" "$TOKEN" >"$TOKEN_FILE"
unset TOKEN

existing_id="$(
  op item list --vault "$VAULT" --format json |
    jq -r --arg title "$ITEM_TITLE" '.[] | select(.title == $title) | .id' |
    head -n 1
)"

if [[ -n "$existing_id" ]]; then
  op item get "$existing_id" --vault "$VAULT" --format json >"$TEMPLATE_FILE"
  jq \
    --rawfile token "$TOKEN_FILE" \
    --arg title "$ITEM_TITLE" \
    --arg field "$FIELD_NAME" \
    '.title = $title
     | .fields = [
        {
          id: $field,
          type: "CONCEALED",
          purpose: "PASSWORD",
          label: $field,
          value: $token
        },
        {
          id: "notesPlain",
          type: "STRING",
          purpose: "NOTES",
          label: "notesPlain",
          value: "Fine-grained GitHub token for repository metadata maintenance."
        }
      ]' "$TEMPLATE_FILE" >"$PAYLOAD_FILE"
  op item edit "$existing_id" --vault "$VAULT" --template "$PAYLOAD_FILE" --tags "$TAGS" >/dev/null
  echo "Updated 1Password item: $ITEM_TITLE"
else
  op item template get Password >"$TEMPLATE_FILE"
  jq \
    --rawfile token "$TOKEN_FILE" \
    --arg title "$ITEM_TITLE" \
    --arg field "$FIELD_NAME" \
    '.title = $title
     | .fields = [
        {
          id: $field,
          type: "CONCEALED",
          purpose: "PASSWORD",
          label: $field,
          value: $token
        },
        {
          id: "notesPlain",
          type: "STRING",
          purpose: "NOTES",
          label: "notesPlain",
          value: "Fine-grained GitHub token for repository metadata maintenance."
        }
      ]' "$TEMPLATE_FILE" >"$PAYLOAD_FILE"
  op item create --vault "$VAULT" --tags "$TAGS" --template "$PAYLOAD_FILE" >/dev/null
  echo "Created 1Password item: $ITEM_TITLE"
fi
