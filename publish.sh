#!/usr/bin/env bash
# =============================================================================
# Publish this repository to github.com/sam3gp8/Ollama-HA-GPU
#
# Run from the repo root. Requires either:
#   a) GitHub CLI (`gh`) authenticated as sam3gp8 — creates the repo AND
#      pushes in one shot, or
#   b) an empty repo already created at github.com/sam3gp8/Ollama-HA-GPU and
#      git credentials (SSH key or HTTPS token) configured locally.
# =============================================================================
set -euo pipefail

REPO="sam3gp8/Ollama-HA-GPU"
BRANCH="main"

cd "$(dirname "$0")"

if [ ! -d .git ]; then
    git init -b "${BRANCH}"
fi

git add -A
if git diff --cached --quiet; then
    echo "Nothing new to commit."
else
    git commit -m "haos-gpu-ai: ollama_notimeout add-on + daily Ollama auto-tracking CI"
fi

if command -v gh >/dev/null 2>&1; then
    if gh repo view "${REPO}" >/dev/null 2>&1; then
        echo "Repo ${REPO} exists — pushing."
        git remote get-url origin >/dev/null 2>&1 || \
            git remote add origin "https://github.com/${REPO}.git"
        git push -u origin "${BRANCH}"
    else
        echo "Creating ${REPO} and pushing."
        gh repo create "${REPO}" --public --source . --push
    fi
else
    echo "gh CLI not found — using plain git."
    echo "Create an empty repo named 'haos-gpu-ai' at https://github.com/new first if it doesn't exist."
    git remote get-url origin >/dev/null 2>&1 || \
        git remote add origin "git@github.com:${REPO}.git"
    git push -u origin "${BRANCH}"
fi

echo
echo "Done. Add-on store URL to add in HA:"
echo "  https://github.com/${REPO}"
echo
echo "After the first push, enable the auto-tracker:"
echo "  - Settings → Actions → General → Workflow permissions:"
echo "    'Read and write permissions' + 'Allow GitHub Actions to create and approve pull requests'"
echo "  - The daily cron starts on its own; trigger a test run from the Actions tab"
echo "    ('Track Ollama releases' → Run workflow)."
