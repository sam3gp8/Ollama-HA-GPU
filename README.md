# Ollama-HA-GPU

Home Assistant add-on repository — [sam3gp8](https://github.com/sam3gp8)

[![Lint](https://github.com/sam3gp8/Ollama-HA-GPU/actions/workflows/lint.yml/badge.svg)](https://github.com/sam3gp8/Ollama-HA-GPU/actions/workflows/lint.yml)
[![Track Ollama releases](https://github.com/sam3gp8/Ollama-HA-GPU/actions/workflows/track-ollama.yml/badge.svg)](https://github.com/sam3gp8/Ollama-HA-GPU/actions/workflows/track-ollama.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-sam3gp8-yellow?logo=buymeacoffee)](https://www.buymeacoffee.com/sam3gp8)

GPU-accelerated add-ons for the custom tri-vendor HAOS GPU-AI build.

## Add-ons

- **[ollama_notimeout](./ollama_notimeout)** — Ollama server tuned to never
  time out loading/unloading models regardless of size, with GPU device
  passthrough for custom HAOS builds. Debian/glibc-based (Ollama's official
  binaries don't run on the Alpine/musl HA base image).

## Why this repo is separate from the OS build

The OS image (the tri-vendor HAOS GPU-AI fork) only rebuilds when a new HAOS
version is released — a slow cadence, measured in months, gated on upstream.
Ollama, by contrast, ships a new release every few days. Pinning the Ollama
version inside the OS image would chain the two cadences together and leave
the add-on stale between OS rebuilds.

Keeping the add-on here, tracked on **Ollama's** cadence, decouples them: the
host image provides the stable driver/runtime layer and changes rarely; the
add-on carries Ollama and updates on its own clock.

## Auto-tracking

`.github/workflows/track-ollama.yml` runs daily. When a newer **stable**
Ollama release exists **and** its Linux release assets actually resolve
(both amd64 and arm64 `.tar.zst` — the guard that catches naming changes and
phantom tags), it bumps the pin in `ollama_notimeout/Dockerfile`, bumps the
add-on version, prepends a changelog entry, and **opens a pull request**.

It opens a PR rather than pushing to `main` on purpose. A new Ollama runner
can change llama.cpp/CUDA behavior — the `cuda_v13` PTX-JIT path on the 4090
is the known example — so each bump gets a review gate: skim the release
notes, rebuild, load a model, confirm warmup completes, then merge. Nothing
reaches the live appliance until you merge and the device refreshes its store.

Manual check: Actions → **Track Ollama releases** → **Run workflow**.

## Install as a repository (recommended)

Settings → Apps → App Store → ⋮ → Repositories → add:

```
https://github.com/sam3gp8/Ollama-HA-GPU
```

The add-on then appears in the store under this repository's name, with
update notifications like any other app.

## Install as a local app (no GitHub push required)

Copy just the `ollama_notimeout/` folder into `/addons/local/` on the HAOS
host — one level deep, so `/addons/local/ollama_notimeout/config.yaml`
exists — then App Store → ⋮ → Reload. It shows up under **Local**.

## First-time setup after pushing

1. Run `./publish.sh` (uses `gh` if available, else plain git).
2. Settings → Actions → General → Workflow permissions: enable
   **Read and write permissions** and **Allow GitHub Actions to create and
   approve pull requests** (required for the tracker to open PRs).
3. The daily cron starts on its own; trigger one run manually to confirm.

## Support

If this saves you time: [buymeacoffee.com/sam3gp8](https://www.buymeacoffee.com/sam3gp8)
