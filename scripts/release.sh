#!/usr/bin/env bash
#
# Release helper for the KHInsider client.
#
# Usage:
#   ./scripts/release.sh patch|minor|major [--dry-run]
#       Bump the version in app/pubspec.yaml, commit "chore(release): vX.Y.Z",
#       tag vX.Y.Z and push (branch + tag) — triggers the release CI.
#
#   ./scripts/release.sh repin [vX.Y.Z] [--dry-run]
#       Re-point an existing release tag to the CURRENT commit and force-push
#       it — used when CI failed, you fixed the workflow, and want to re-run
#       the same release. Also deletes the GitHub release for that tag first
#       so assets are rebuilt cleanly (requires `gh`).
#
# Options:
#   --dry-run    Print what would happen, change nothing.
#
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION_FILE="app/pubspec.yaml"
DRY_RUN=0

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

current_version() {
  grep -E '^version:' "$VERSION_FILE" | head -1 |
    sed -E 's/version:[[:space:]]*//' | sed -E 's/\+.*//'
}

current_build() {
  grep -E '^version:' "$VERSION_FILE" | head -1 |
    sed -E 's/.*\+//' | grep -E '^[0-9]+$' || echo 0
}

bump_version() {
  local part=$1 version=$2
  local MA MI PA
  IFS='.' read -r MA MI PA <<< "$version"
  case "$part" in
    major) echo "$((MA + 1)).0.0" ;;
    minor) echo "$MA.$((MI + 1)).0" ;;
    patch) echo "$MA.$MI.$((PA + 1))" ;;
    *) usage ;;
  esac
}

require_clean_tree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean — commit or stash first."
    git status --short
    exit 1
  fi
}

run() {
  echo "+ $*"
  [[ "$DRY_RUN" == 1 ]] || "$@"
}

# ---------------------------------------------------------------------------
main=${ARGS[0]:-}

case "$main" in
  patch | minor | major)
    require_clean_tree
    OLD=$(current_version)
    NEW=$(bump_version "$main" "$OLD")
    BUILD=$(current_build)
    TAG="v$NEW"

    echo "Release: $OLD -> $NEW (tag $TAG, build +$BUILD)"
    [[ "$DRY_RUN" == 1 ]] && exit 0

    # Bump version in pubspec (keep the +build suffix pattern).
    #
    # awk rather than `sed -i`: the GNU-only `0,/re/` address used to be here,
    # and BSD/macOS sed parses it as a no-op — the version silently stayed put
    # and the release commit came out empty. This replaces the first
    # `version:` line and leaves every other byte alone.
    awk -v v="$NEW+$BUILD" '
      !found && /^version:/ { print "version: " v; found = 1; next }
      { print }
    ' "$VERSION_FILE" > "$VERSION_FILE.tmp"
    mv "$VERSION_FILE.tmp" "$VERSION_FILE"
    grep -q "^version: $NEW+$BUILD\$" "$VERSION_FILE" ||
      { echo "ERROR: version bump failed ($VERSION_FILE)"; exit 1; }

    git add "$VERSION_FILE"
    git commit -m "chore(release): $TAG"
    git tag "$TAG"
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    run git push origin "$BRANCH" "$TAG"
    echo "Done. CI will build and publish the release for $TAG."
    ;;

  repin)
    TAG=${ARGS[1]:-}
    if [[ -z "$TAG" ]]; then
      TAG=$(git tag --sort=-v:refname | head -1)
      [[ -z "$TAG" ]] && { echo "ERROR: no tags found."; exit 1; }
    fi
    require_clean_tree

    echo "Repinning $TAG -> HEAD ($(git rev-parse --short HEAD))"
    [[ "$DRY_RUN" == 1 ]] && exit 0

    # Drop the old GitHub release so assets are rebuilt from scratch.
    if command -v gh >/dev/null 2>&1; then
      gh release delete "$TAG" -y --cleanup-tag || true
    else
      echo "(gh not found — skipping GitHub release deletion)"
      git push origin ":refs/tags/$TAG" || true
    fi

    git tag -f "$TAG" HEAD
    run git push origin "$TAG" --force
    echo "Done. Tag $TAG now points at $(git rev-parse --short HEAD); CI will rebuild the release."
    ;;

  *)
    usage
    ;;
esac
