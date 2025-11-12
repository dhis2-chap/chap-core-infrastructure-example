#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/dhis2-chap/chap-core.git"

# Fetch all tags (only the tag names, strip refs)
tags=$(git ls-remote --tags --refs "$REPO_URL" | awk '{print $2}' | sed 's#refs/tags/##')

if [[ -z "$tags" ]]; then
  echo "No tags found in $REPO_URL" >&2
  exit 1
fi

# Sort tags semantically and pick the latest one
latest_tag=$(echo "$tags" | sort -V | tail -n 1)

# Output only the tag
echo "$latest_tag"
