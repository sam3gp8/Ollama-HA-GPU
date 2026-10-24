# Changelog

## 1.1.6 — Ollama 0.40.10 (auto-tracked 2026-10-24)
- Bumped bundled Ollama to v0.40.10 (was v0.40.8), tracked
  automatically from upstream stable releases. Release assets for
  amd64 and arm64 were verified present before this bump.
- NOTE: a new Ollama runner can change llama.cpp/CUDA behavior
  (e.g. the cuda_v13 PTX-JIT path). Test gemma4:26b load on the
  4090 before relying on this in production.

## 1.1.5 — Ollama 0.40.8 (auto-tracked 2026-10-22)
- Bumped bundled Ollama to v0.40.8 (was v0.31.1), tracked
  automatically from upstream stable releases. Release assets for
  amd64 and arm64 were verified present before this bump.
- NOTE: a new Ollama runner can change llama.cpp/CUDA behavior
  (e.g. the cuda_v13 PTX-JIT path). Test gemma4:26b load on the
  4090 before relying on this in production.

## 1.1.4 — schema migration fix
- **Fixed: `update.install` failing with `invalid options: value must be
  one of ['auto', 'off', 'on']. Got {... 'flash_attention': True ...}`.**
  1.1.3 changed the option's *type* in place (bool → list), and Supervisor
  validates stored user options against the new schema before installing —
  so any existing install with the boolean saved could not update. Worse,
  the 1.1.3 changelog's "re-save in Configuration" advice was impossible:
  the installed version's UI only offers a boolean toggle, and its own
  schema rejects strings. Owning that one.
- Correct migration per the HA app-config docs: **rename the key** —
  `flash_attention` → `flash_attention_mode`. The stored legacy boolean
  becomes an unknown key, which Supervisor strips with a warning
  (`Option 'flash_attention' does not exist in the schema`) instead of
  failing; the new key picks up its `auto` default. Update proceeds with
  no manual intervention.
- Note for anyone who had the legacy toggle set: your on/off preference
  is discarded by the migration (defaults to `auto`). If you want FA
  forced on — e.g. for `kv_cache_type: q8_0` — set Flash attention = on
  in Configuration after updating; the runtime guard covers the pairing
  either way.

## 1.1.3 — flash attention / KV cache quantization
- **Fixed: `llama-server process has terminated: V cache quantization
  requires flash_attn` (HTTP 500 at model load).** Two compounding design
  errors: (a) the old `flash_attention: bool` option force-exported
  `OLLAMA_FLASH_ATTENTION=false` by default, which both disabled Ollama's
  own per-model auto-FA and made any KV-cache quantization (e.g. set via
  `extra_env`) a guaranteed llama.cpp load failure; (b) nothing validated
  the final env combination.
- `flash_attention` is now tri-state `auto|on|off` (default `auto` =
  leave `OLLAMA_FLASH_ATTENTION` unset; per the official FAQ, Ollama then
  decides per model/hardware — FA is architecture-gated).
- New first-class `kv_cache_type` option: `default|f16|q8_0|q4_0`
  (default `default` = don't export; q8_0 ≈ half KV VRAM, near-lossless).
- Post-flight guard runs AFTER `extra_env`: if the final env has a
  quantized `OLLAMA_KV_CACHE_TYPE` without FA explicitly on, the app
  forces `OLLAMA_FLASH_ATTENTION=1` and logs a warning — the crash combo
  is now unreachable no matter where either value came from.
- **Fixed (latent, found via functional testing):** `json_or` previously
  swallowed jq failures — a missing/corrupt `options.json` (or missing jq)
  would export every `OLLAMA_*` var as an empty string, silently reverting
  `keep_alive`/`load_timeout` to Ollama's 5-minute defaults: the exact
  timeouts this app exists to eliminate. It now falls back to the built-in
  defaults on any jq failure or empty value, with a warning when
  `options.json` is absent. Verified with eight functional scenarios
  including corrupt and missing options files.
- **One-time migration note:** the stored `flash_attention` value from
  ≤1.1.2 is a boolean and will fail the new `list(auto|on|off)` schema.
  If the app refuses to start after updating with an options-validation
  error, open Configuration, set Flash attention to `auto` (or `on`/
  `off`), and Save. This is a one-time re-save.

## 1.1.2 — NVIDIA GPU detection
- **Fixed: RTX 4090 (and any NVIDIA GPU) not detected.** The
  nvidia-container-toolkit hook — active via `default-runtime: nvidia` on
  the custom HAOS GPU build — only injects `/dev/nvidia*` and the host
  driver userspace (`libcuda.so`, `libnvidia-ml.so`, `nvidia-smi`) when
  the container sets `NVIDIA_VISIBLE_DEVICES`. The stock `ollama/ollama`
  image bakes this in, which is why it detected the GPU and this image
  didn't. Now sets `NVIDIA_VISIBLE_DEVICES=all` and
  `NVIDIA_DRIVER_CAPABILITIES=compute,utility`. Harmless on non-NVIDIA
  hosts.
- Docs: `gpu_devices` clarified as AMD/ROCm numeric indices only — leave
  blank for NVIDIA (use `extra_env` → `CUDA_VISIBLE_DEVICES` to pin
  cards). Names like `4090 RTX` break Ollama discovery.

## 1.1.1 — audit pass
- **Fixed (real bug):** `finish` script now uses s6's actual argument
  semantics — a signal death arrives as `$1=256` with the signal number in
  `$2`, not the shell-style `137`. The OOM-kill detection would never have
  fired as previously written.
- **Fixed (inaccurate mechanism):** removed `S6_SERVICES_GRACETIME` — it
  only governs legacy `/etc/services.d` services, which this image no
  longer uses, so it was inert. Graceful-stop time is now controlled by
  the documented `timeout: 120` key in `config.yaml` (Supervisor's Docker
  stop timeout, default 10s). s6-rc itself waits indefinitely (no
  `timeout-kill` file).
- **Fixed (dead config):** removed `backup_exclude` — it only filters the
  app's own `/data` backup; models live in `/share`, a separate backup
  component it cannot touch. README now gives accurate backup guidance.
- **Fixed (latent bug):** option parsing no longer uses jq's `//`
  operator, which treats boolean `false` as absent — an explicit
  `flash_attention: false` was being silently discarded and only worked
  because the fallback happened to match. Replaced with a null-aware
  helper.
- **Fixed (wrong CI tool):** removed hassfest from the lint workflow —
  it validates custom integrations, not app repositories. The addon
  linter remains.
- Added `/etc/s6-overlay/s6-rc.d/ollama/dependencies.d/base` so the
  service starts after s6-overlay's base bundle.
- Repo/publishing: all URLs unified to `github.com/sam3gp8/ha-addons`,
  added `.github/FUNDING.yml` (Buy Me a Coffee: sam3gp8), added
  `publish.sh`.
- Verified against the current app configuration reference:
  `init: false` (required for s6-overlay v3), plain-host-path `devices`,
  dict-format `map`, and all schema types were already correct.

## 1.1.0
- **Root cause of "ollama: not found" after a successful download/extract:**
  the HA base image (`ghcr.io/home-assistant/base`) is Alpine/musl.
  Ollama's official Linux binary is glibc-linked (`/lib64/ld-linux-x86-64.so.2`),
  and bundles hundreds of MB of CUDA/ROCm `.so` files that are themselves
  glibc binaries — not just a loader-path issue but a full libc/libstdc++
  ABI mismatch. Alpine's own wiki calls the usual gcompat workaround
  unreliable for production use, so patching around it wasn't the right
  call for something meant to load 70B+ models reliably.
- Switched base image to `debian:bookworm-slim` (glibc-native). Supervisor
  2026.04.0+ no longer requires the HA base image, so this is fully
  supported under the current App builder.
- s6-overlay v3 is now installed manually (noarch + arch tarballs from
  just-containers/s6-overlay) since the HA base image previously provided
  this. Service definition moved from the legacy `/etc/services.d/`
  format to the current `/etc/s6-overlay/s6-rc.d/<name>/{run,type,finish}`
  + `/etc/s6-overlay/s6-rc.d/user/contents.d/<name>` longrun format.
- `run`/`finish` scripts rewritten to read `/data/options.json` via `jq`
  directly instead of `bashio` — bashio was only ever supplied by the HA
  base image, not something intrinsic to being an App, so it's gone along
  with Alpine.
- Confirmed Ollama's `.tar.zst` release layout (`bin/ollama`, `lib/ollama/`)
  extracts correctly to `/usr` by directly inspecting the downloaded
  archive rather than assuming.

## 1.0.2
- Fixed: Ollama dropped `.tgz` release assets for Linux in favor of
  `.tar.zst` (zstd) — the old URL 404'd. Now downloads `.tar.zst` and
  decompresses via `zstd` (Alpine's busybox `tar` has no native zstd
  support, hence the explicit pipe rather than `tar --zstd`)
- Bumped default `OLLAMA_VERSION` to 0.31.1 (confirmed real, non-RC,
  current stable tag as of this writing — verify against
  github.com/ollama/ollama/releases before relying on it long-term,
  ollama ships new tags roughly every 1-2 days)

## 1.0.1
- Fixed: removed deprecated `build.yaml` (retired with the 2026-04-02
  builder migration); `FROM`/`LABEL`/`ARG` now live directly in the
  Dockerfile, pointed at the correct `ghcr.io/home-assistant/base` image
  (was incorrectly pointing at the unrelated community `hassio-addons/base`
  image with a nonexistent tag)
- Fixed: `libstc++` typo in apk install → `libstdc++`
- Fixed: `devices` updated to current plain-host-path format
- Fixed: `map` updated to current `type`/`read_only` dict format
- Added: `backup_exclude` for the model storage path

## 1.0.0
- Initial release
- OLLAMA_LOAD_TIMEOUT=0 and OLLAMA_KEEP_ALIVE=-1 forced regardless of options
- No Supervisor watchdog/healthcheck declared, by design
- Generic GPU device passthrough placeholders (/dev/dri, /dev/kfd) — edit for your build
- 600s s6 shutdown gracetime to avoid corrupting model cache on stop/restart
- finish script flags OOM kills (exit 137) distinctly from other exits
