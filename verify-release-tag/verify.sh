#!/usr/bin/env bash
# Checks that the pushed tag is annotated, names the version, and has release notes.
#   VERSION=X.Y.Z verify.sh   (run from the checked-out tag, with GH_TOKEN set)
set -euo pipefail
tag=$GITHUB_REF_NAME
test -n "${VERSION:-}" || { echo "no version given" >&2; exit 1; }
test "$tag" = "v$VERSION" || { echo "tag $tag does not match version $VERSION" >&2; exit 1; }
type=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$tag" --jq .object.type)
test "$type" = tag || { echo "tag $tag is not annotated" >&2; exit 1; }
notes="release-notes/$tag.md"
test -f "$notes" && test ! -L "$notes" && grep -q '[^[:space:]]' "$notes" \
    || { echo "missing or empty $notes" >&2; exit 1; }
echo "$tag is annotated, matches the version, and has release notes"
