#!/bin/bash
# Resets labels on specified repos — removes all existing labels and applies
# the predefined set from a JSON file.
# Requires: gh (GitHub CLI), authenticated via `gh auth login`

# ── Configuration ────────────────────────────────────────────────────────────
OWNER=""   # e.g. markbattistella
REPOS=(    # Array of repos, e.g. "EmbeeKit" "AudioManager"
           # Leave empty to target all repos for OWNER
)
# Path to the label definitions file (defaults to sibling issue-labels.json)
JSON_FILE="$(dirname "$0")/issue-labels.json"
# ─────────────────────────────────────────────────────────────────────────────

if [ -z "$OWNER" ]; then
  echo "Error: OWNER is not set."
  exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
  echo "Error: Label file not found at '$JSON_FILE'."
  exit 1
fi

# If REPOS is empty, fetch all repos for the owner
if [ ${#REPOS[@]} -eq 0 ]; then
  echo "No repos specified — fetching all repos for '$OWNER'..."

  # Check if authenticated as the owner to determine access level
  AUTHED_USER=$(gh api user --jq '.login' 2>/dev/null)

  FETCHED=()
  PAGE=1

  while true; do
    if [ "$AUTHED_USER" = "$OWNER" ]; then
      # Authenticated as owner — use /user/repos to include private repos
      BATCH=$(gh api "user/repos?per_page=100&page=$PAGE&affiliation=owner" --jq '.[].name' 2>&1)
    else
      # Not authenticated as owner — public repos only
      BATCH=$(gh api "users/$OWNER/repos?per_page=100&page=$PAGE" --jq '.[].name' 2>&1)
    fi

    if [ -z "$BATCH" ]; then
      break
    fi

    # IFS= prevents word splitting; -r prevents backslash interpretation
    while IFS= read -r REPO; do
      FETCHED+=("$REPO")
    done <<< "$BATCH"

    # If fewer than 100 results, we've hit the last page
    # tr -d ' ' trims the whitespace that wc -l includes on macOS
    BATCH_COUNT=$(echo "$BATCH" | wc -l | tr -d ' ')
    if [ "$BATCH_COUNT" -lt 100 ]; then
      break
    fi

    PAGE=$((PAGE + 1))
  done

  REPOS=("${FETCHED[@]}")
  echo "Found ${#REPOS[@]} repos."
  echo ""
fi

# Track results across all repos
SUCCEEDED=()
FAILED=()

for REPO in "${REPOS[@]}"; do
  # Build the full owner/repo identifier used by the GitHub API
  FULL="$OWNER/$REPO"
  FAIL_REASON=""
  echo "▶ Processing $FULL"

  # Fetch all current label names from the repo
  EXISTING=$(gh api "repos/$FULL/labels?per_page=100" --jq '.[].name' 2>&1) || {
    FAIL_REASON="Could not fetch labels: $EXISTING"
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  }

  # Delete each existing label
  # Using herestring (<<<) keeps the loop in the current shell so FAIL_REASON is visible outside
  while IFS= read -r LABEL; do
    [ -z "$LABEL" ] && continue

    # URL-encode the label name so spaces and colons are safe in the API path
    ENCODED=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" <<< "$LABEL")

    DELETE_OUTPUT=$(gh api "repos/$FULL/labels/$ENCODED" --method DELETE 2>&1) || {
      FAIL_REASON="Could not delete label '$LABEL': $DELETE_OUTPUT"
      break
    }
    echo "  Deleted '$LABEL'"
  done <<< "$EXISTING"

  if [ -n "$FAIL_REASON" ]; then
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  fi

  echo "  All existing labels removed."

  # Add labels from the JSON file
  # Process substitution (< <(...)) keeps the loop in the current shell so FAIL_REASON is visible outside
  while IFS= read -r LABEL_JSON; do
    NAME=$(echo "$LABEL_JSON" | jq -r '.name')
    COLOR=$(echo "$LABEL_JSON" | jq -r '.color')
    DESCRIPTION=$(echo "$LABEL_JSON" | jq -r '.description')

    CREATE_OUTPUT=$(gh api "repos/$FULL/labels" \
      --method POST \
      --field name="$NAME" \
      --field color="$COLOR" \
      --field description="$DESCRIPTION" 2>&1) || {
      FAIL_REASON="Could not create label '$NAME': $CREATE_OUTPUT"
      break
    }
    echo "  Added '$NAME'"
  done < <(jq -c '.[]' "$JSON_FILE")

  if [ -n "$FAIL_REASON" ]; then
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  fi

  echo "  ✓ Labels applied."
  SUCCEEDED+=("$REPO")
  echo ""
done

# ── Report ────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
  echo ""
  echo "✓ Completed (${#SUCCEEDED[@]}):"
  for R in "${SUCCEEDED[@]}"; do
    echo "  • $R"
  done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "✗ Failed (${#FAILED[@]}):"
  for R in "${FAILED[@]}"; do
    echo "  • $R"
  done
fi

echo ""
