#!/usr/bin/env bash
# Fails on floating runner labels and on third-party actions not pinned to a full commit SHA.
#   .github/check-pins.sh [DIR...]   (defaults to the current directory)
set -uo pipefail
dirs=("$@")
[ $# -gt 0 ] || dirs=(.)
files=$(grep -rlE --include='*.yml' --include='*.yaml' '(runs-on|uses):' "${dirs[@]}" | sort -u)
status=0
for f in $files; do
    while IFS= read -r line; do
        echo "$f: floating runner label: $line"; status=1
    done < <(grep -nE 'runs-on:.*-latest' "$f")
    while IFS= read -r line; do
        ref=$(sed -nE 's/.*uses: *([^ #]+).*/\1/p' <<<"$line")
        case $ref in
            ./*|docker://*) continue ;;
            wakamex/release-actions/*@stable|wakamex/release-actions/*@main) continue ;;
        esac
        [[ $ref =~ @[0-9a-f]{40}$ ]] || { echo "$f: action not pinned to a commit SHA: $line"; status=1; }
    done < <(grep -nE '^[^#]*uses: ' "$f")
done
exit $status
