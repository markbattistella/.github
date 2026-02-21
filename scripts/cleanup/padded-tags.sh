#!/bin/bash
# Finds tags with zero-padded months (e.g. 26.02.07) and recreates them
# without the leading zero (e.g. 26.2.7), preserving the original commit SHA.
# Requires: gh (GitHub CLI), authenticated via `gh auth login`

# ── Configuration ────────────────────────────────────────────────────────────
OWNER=""  # markbattistella
REPOS=(   # Array of repos, "EmbeeKit" "AudioManager"
)
# ─────────────────────────────────────────────────────────────────────────────

# Track results across all repos
SUCCEEDED=()
FAILED=()
SKIPPED=()

for REPO in "${REPOS[@]}"; do
  # Build the full owner/repo identifier used by the GitHub API
  FULL="$OWNER/$REPO"
  echo "▶ Processing $FULL"

  # Fetch all tags and their SHAs
  TAGS_JSON=$(gh api "repos/$FULL/git/refs/tags" 2>&1) || {
    FAILED+=("$REPO — Could not fetch tags: $TAGS_JSON")
    echo "  ✗ Could not fetch tags"
    echo ""
    continue
  }

  # Extract all tag names from refs
  ALL_TAGS=$(echo "$TAGS_JSON" | grep -oE '"ref":\s*"refs/tags/[^"]+"' | sed -E 's|"ref":\s*"refs/tags/||;s|"||g')

  # Filter to only those with a zero-padded month or day (yy.0m.dd or yy.mm.0d etc.)
  MATCHED=$(echo "$ALL_TAGS" | grep -E '^[0-9]+\.0[0-9]+\.[0-9]+$|^[0-9]+\.[0-9]+\.0[0-9]+$')

  if [ -z "$MATCHED" ]; then
    echo "  No zero-padded tags found, skipping."
    SKIPPED+=("$REPO")
    echo ""
    continue
  fi

  REPO_HAD_FAILURE=false

  # IFS= prevents word splitting; -r prevents backslash interpretation
  while IFS= read -r OLD_TAG; do
    # Strip leading zeros from month and day segments (e.g. 26.02.07 → 26.2.7)
    NEW_TAG=$(echo "$OLD_TAG" | sed -E 's/^([0-9]+)\.0*([1-9][0-9]*)\.0*([1-9][0-9]*)$/\1.\2.\3/')

    if [ "$OLD_TAG" = "$NEW_TAG" ]; then
      echo "  Skipping '$OLD_TAG' — no change needed."
      continue
    fi

    echo "  Found '$OLD_TAG' → will rename to '$NEW_TAG'"

    # Get the SHA the tag points to
    SHA=$(gh api "repos/$FULL/git/refs/tags/$OLD_TAG" --jq '.object.sha' 2>&1) || {
      FAILED+=("$REPO ($OLD_TAG) — Could not resolve SHA: $SHA")
      echo "  ✗ Could not resolve SHA for '$OLD_TAG'"
      REPO_HAD_FAILURE=true
      continue
    }

    # If it's an annotated tag, dereference to the commit SHA
    OBJ_TYPE=$(gh api "repos/$FULL/git/refs/tags/$OLD_TAG" --jq '.object.type' 2>&1)
    if [ "$OBJ_TYPE" = "tag" ]; then
      SHA=$(gh api "repos/$FULL/git/tags/$SHA" --jq '.object.sha' 2>&1) || {
        FAILED+=("$REPO ($OLD_TAG) — Could not dereference annotated tag: $SHA")
        echo "  ✗ Could not dereference annotated tag '$OLD_TAG'"
        REPO_HAD_FAILURE=true
        continue
      }
    fi

    echo "    SHA: $SHA"

    # Delete the old tag
    DELETE_OUTPUT=$(gh api "repos/$FULL/git/refs/tags/$OLD_TAG" --method DELETE 2>&1) || {
      FAILED+=("$REPO ($OLD_TAG) — Could not delete old tag: $DELETE_OUTPUT")
      echo "  ✗ Could not delete '$OLD_TAG'"
      REPO_HAD_FAILURE=true
      continue
    }
    echo "    Deleted '$OLD_TAG'"

    # Create the new tag
    CREATE_OUTPUT=$(gh api "repos/$FULL/git/refs" \
      --method POST \
      --field ref="refs/tags/$NEW_TAG" \
      --field sha="$SHA" 2>&1) || {
      FAILED+=("$REPO ($OLD_TAG → $NEW_TAG) — Could not create new tag: $CREATE_OUTPUT")
      echo "  ✗ Could not create '$NEW_TAG' (old tag deleted — manual fix needed at SHA: $SHA)"
      REPO_HAD_FAILURE=true
      continue
    }
    echo "    Created '$NEW_TAG'"

    SUCCEEDED+=("$REPO: $OLD_TAG → $NEW_TAG")
  done <<< "$MATCHED"

  echo ""
done

# ── Report ────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
  echo ""
  echo "✓ Renamed (${#SUCCEEDED[@]}):"
  for R in "${SUCCEEDED[@]}"; do
    echo "  • $R"
  done
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo ""
  echo "— Skipped, nothing to fix (${#SKIPPED[@]}):"
  for R in "${SKIPPED[@]}"; do
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
