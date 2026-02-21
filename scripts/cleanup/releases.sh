#!/bin/bash
# Deletes all releases (not tags) from each repo, then creates a new lightweight tag.
# Requires: gh (GitHub CLI), authenticated via `gh auth login`

# ── Configuration ────────────────────────────────────────────────────────────
OWNER=""  # markbattistella
TAG=""    # "26.01.31"
REPOS=(   # Array of repos, "EmbeeKit" "AudioManager"
)
# ─────────────────────────────────────────────────────────────────────────────

# Track results across all repos
SUCCEEDED=()
FAILED=()

for REPO in "${REPOS[@]}"; do
  # Build the full owner/repo identifier used by the GitHub API
  FULL="$OWNER/$REPO"
  FAIL_REASON=""
  echo "▶ Processing $FULL"

  # Delete all releases (leaves tags intact)
  RELEASE_TAGS=$(gh release list --repo "$FULL" --limit 100 --json tagName --jq '.[].tagName' 2>&1) || {
    FAIL_REASON="Could not list releases: $RELEASE_TAGS"
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  }

  if [ -z "$RELEASE_TAGS" ]; then
    echo "  No releases found."
  else
    for TAG_NAME in $RELEASE_TAGS; do
      echo "  Deleting release '$TAG_NAME'..."
      DELETE_OUTPUT=$(gh release delete "$TAG_NAME" --repo "$FULL" --yes 2>&1) || {
        FAIL_REASON="Failed to delete release '$TAG_NAME': $DELETE_OUTPUT"
        break
      }
    done

    if [ -n "$FAIL_REASON" ]; then
      FAILED+=("$REPO — $FAIL_REASON")
      echo "  ✗ $FAIL_REASON"
      echo ""
      continue
    fi

    echo "  All releases deleted."
  fi

  # Create a new lightweight tag on the default branch's latest commit
  SHA=$(gh api "repos/$FULL/commits/HEAD" --jq '.sha' 2>&1) || {
    FAIL_REASON="Could not resolve HEAD commit: $SHA"
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  }

  echo "  Creating tag $TAG at $SHA..."
  TAG_OUTPUT=$(gh api "repos/$FULL/git/refs" \
    --method POST \
    --field ref="refs/tags/$TAG" \
    --field sha="$SHA" 2>&1) || {
    # HTTP 422 Unprocessable Entity means the tag reference already exists
    if echo "$TAG_OUTPUT" | grep -q "422"; then
      FAIL_REASON="Tag '$TAG' already exists"
    else
      FAIL_REASON="Failed to create tag: $TAG_OUTPUT"
    fi
    FAILED+=("$REPO — $FAIL_REASON")
    echo "  ✗ $FAIL_REASON"
    echo ""
    continue
  }

  echo "  ✓ Tag $TAG created."
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
