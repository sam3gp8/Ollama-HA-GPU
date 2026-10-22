#!/usr/bin/env bash
# =============================================================================
# check-ollama-version.sh
#
# Compares the OLLAMA_VERSION currently pinned in ollama_notimeout/Dockerfile
# against the latest stable Ollama release on GitHub. If a newer stable
# version exists AND its Linux release assets actually resolve (both amd64
# and arm64 .tar.zst), it rewrites the pin in the Dockerfile and bumps the
# add-on version in config.yaml.
#
# Writes machine-readable results to $GITHUB_OUTPUT when run in Actions, and
# prints a human summary either way. Makes NO git commits itself — the
# workflow decides what to do with the changes.
#
# Exit codes:
#   0  success (whether or not an update was applied; see `updated` output)
#   1  hard error (missing files, API failure, asset verification failed on
#      a version that otherwise looked newer)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/ollama_notimeout/Dockerfile"
CONFIG_YAML="${REPO_ROOT}/ollama_notimeout/config.yaml"
CHANGELOG="${REPO_ROOT}/ollama_notimeout/CHANGELOG.md"

# Allow override for testing; default to the real API.
OLLAMA_API="${OLLAMA_API:-https://api.github.com/repos/ollama/ollama/releases/latest}"
ASSET_BASE="${ASSET_BASE:-https://github.com/ollama/ollama/releases/download}"

log()  { printf '%s\n' "$*" >&2; }
emit() { # emit key=value to GITHUB_OUTPUT if present
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    fi
}

for f in "${DOCKERFILE}" "${CONFIG_YAML}"; do
    [ -f "$f" ] || { log "ERROR: missing ${f}"; exit 1; }
done

# --- current pin -----------------------------------------------------------
CURRENT="$(grep -oP 'ARG OLLAMA_VERSION="\K[0-9]+\.[0-9]+\.[0-9]+(?=")' "${DOCKERFILE}" || true)"
if [ -z "${CURRENT}" ]; then
    log "ERROR: could not parse current OLLAMA_VERSION from ${DOCKERFILE}"
    exit 1
fi
log "Current pin: ${CURRENT}"

# --- latest stable from GitHub --------------------------------------------
# curl flags: -sSL follow redirects, fail loudly on HTTP errors.
AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

RELEASE_JSON="$(curl -sSL --fail "${AUTH[@]}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${OLLAMA_API}")" || { log "ERROR: GitHub API request failed"; exit 1; }

# /releases/latest already excludes prereleases and drafts, so tag_name is
# the latest STABLE. Strip a leading v.
LATEST="$(printf '%s' "${RELEASE_JSON}" | jq -r '.tag_name' | sed 's/^v//')"
if [ -z "${LATEST}" ] || [ "${LATEST}" = "null" ]; then
    log "ERROR: could not read latest tag from API response"
    exit 1
fi
log "Latest stable: ${LATEST}"

emit "current" "${CURRENT}"
emit "latest" "${LATEST}"

# --- semver compare (returns the greater of two X.Y.Z) ---------------------
greater() {
    # prints the larger version; if equal prints $1
    printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1
}

if [ "${CURRENT}" = "${LATEST}" ]; then
    log "Already on latest stable (${CURRENT}). Nothing to do."
    emit "updated" "false"
    emit "reason" "up-to-date"
    exit 0
fi

if [ "$(greater "${CURRENT}" "${LATEST}")" = "${CURRENT}" ]; then
    # Current pin is newer than "latest stable" — happens if we manually
    # pinned a prerelease or the API lags. Do not downgrade.
    log "Current pin ${CURRENT} is >= latest stable ${LATEST}; not downgrading."
    emit "updated" "false"
    emit "reason" "current-newer"
    exit 0
fi

# --- verify the new version's assets actually exist ------------------------
# This is the guard that would have caught the .tgz->.tar.zst break and the
# 0.30.12 404. We HEAD both arch assets; a redirect to the CDN is expected,
# so -L and treat 200/206 (and 302-followed-to-200) as success.
verify_asset() {
    local arch="$1"
    local url="${ASSET_BASE}/v${LATEST}/ollama-linux-${arch}.tar.zst"
    local code
    code="$(curl -sSL -o /dev/null -w '%{http_code}' --range 0-0 "${url}" || echo 000)"
    log "  ${arch}: ${url} -> HTTP ${code}"
    case "${code}" in
        200|206) return 0 ;;
        *) return 1 ;;
    esac
}

log "Verifying release assets for v${LATEST}..."
ASSETS_OK=true
verify_asset "amd64" || ASSETS_OK=false
verify_asset "arm64" || ASSETS_OK=false

if [ "${ASSETS_OK}" != "true" ]; then
    log "ERROR: v${LATEST} assets did not verify (missing .tar.zst, or naming changed)."
    log "Refusing to bump the pin to a version that will not build."
    emit "updated" "false"
    emit "reason" "assets-missing"
    exit 1
fi

# --- compute the new add-on version (patch bump) ---------------------------
ADDON_CURRENT="$(grep -oP '^version:\s*"\K[0-9]+\.[0-9]+\.[0-9]+(?=")' "${CONFIG_YAML}" || true)"
if [ -z "${ADDON_CURRENT}" ]; then
    log "ERROR: could not parse add-on version from ${CONFIG_YAML}"
    exit 1
fi
IFS='.' read -r AMAJ AMIN APATCH <<< "${ADDON_CURRENT}"
ADDON_NEW="${AMAJ}.${AMIN}.$((APATCH + 1))"
log "Add-on version: ${ADDON_CURRENT} -> ${ADDON_NEW}"

# --- apply edits -----------------------------------------------------------
# Dockerfile pin
sed -i "s/ARG OLLAMA_VERSION=\"${CURRENT}\"/ARG OLLAMA_VERSION=\"${LATEST}\"/" "${DOCKERFILE}"
# config.yaml add-on version
sed -i "s/^version: \"${ADDON_CURRENT}\"/version: \"${ADDON_NEW}\"/" "${CONFIG_YAML}"

# --- prepend a changelog entry --------------------------------------------
if [ -f "${CHANGELOG}" ]; then
    TODAY="$(date -u +%Y-%m-%d)"
    TMP="$(mktemp)"
    {
        echo "# Changelog"
        echo
        echo "## ${ADDON_NEW} — Ollama ${LATEST} (auto-tracked ${TODAY})"
        echo "- Bumped bundled Ollama to v${LATEST} (was v${CURRENT}), tracked"
        echo "  automatically from upstream stable releases. Release assets for"
        echo "  amd64 and arm64 were verified present before this bump."
        echo "- NOTE: a new Ollama runner can change llama.cpp/CUDA behavior"
        echo "  (e.g. the cuda_v13 PTX-JIT path). Test gemma4:26b load on the"
        echo "  4090 before relying on this in production."
        echo
        # drop the old leading "# Changelog" + blank line, keep the rest
        tail -n +2 "${CHANGELOG}" | sed '1{/^$/d}'
    } > "${TMP}"
    mv "${TMP}" "${CHANGELOG}"
fi

emit "updated" "true"
emit "reason" "bumped"
emit "addon_version" "${ADDON_NEW}"
log "Updated: Ollama ${CURRENT} -> ${LATEST}, add-on ${ADDON_CURRENT} -> ${ADDON_NEW}"
