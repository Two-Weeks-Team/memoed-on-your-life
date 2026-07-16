#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

tracked_environment_files="$(
  git ls-files | awk '/(^|\/)\.env$|(^|\/)\.dev\.vars$|xcuserdata|(^|\/)\.DS_Store$/ { print }'
)"
if [[ -n "$tracked_environment_files" ]]; then
  echo "Tracked local or environment files are prohibited:"
  echo "$tracked_environment_files"
  exit 1
fi

if git grep -nE \
  '(sk-(proj|admin|svcacct)-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{16,}|ghp_[A-Za-z0-9]{16,}|OPENAI_API_KEY[[:space:]]*=[[:space:]]*[^[:space:]#]+|CLOUDFLARE_API_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]#]+)' \
  -- . ':!scripts/repository-cleanliness.sh'; then
  echo "A credential-shaped value was found in tracked content."
  exit 1
fi

if git grep -niE \
  '(donor (repo|code|vessel)|private[- ]prep|previous (repo|product)|legacy product|refit|forgetfulness|/Users/[^/]+/Documents/GitHub/)' \
  -- . ':!scripts/repository-cleanliness.sh'; then
  echo "Prohibited origin or workstation provenance was found in public content."
  exit 1
fi

echo "Repository cleanliness checks passed."
