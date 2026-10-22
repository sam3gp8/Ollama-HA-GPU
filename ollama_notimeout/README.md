# Ollama (No-Timeout GPU) — HAOS App (formerly "add-on")

Local Ollama server for a custom HAOS build with GPU passthrough already
working at the OS/Supervisor level. This app's only job is to make sure
none of the *other* layers between you and the model impose a timeout that
Ollama itself doesn't have.

> **Note on terminology / build system:** as of Supervisor 2026.04.0, HA
> renamed add-ons to "Apps" and retired `build.yaml` in favor of putting
> `FROM`, `LABEL`, and `ARG` directly in the Dockerfile (BuildKit-based).
> This package targets that current schema. If your Supervisor predates
> 2026.04.0, you're on the legacy builder and will need `build.yaml` back
> — check `supervisor --version` if the build fails with base-image errors.

> **Note on base image:** this app deliberately does NOT use
> `ghcr.io/home-assistant/base` (Alpine/musl) — Ollama's official Linux
> binary is glibc-linked and bundles glibc-linked CUDA/ROCm runtime
> libraries, which don't run on musl. It's built on `debian:bookworm-slim`
> with s6-overlay installed manually instead. There's no `bashio` here as
> a result — options are read via `jq` against `/data/options.json`
> directly in `rootfs/etc/s6-overlay/s6-rc.d/ollama/run`.

## Why models "time out" even though Ollama has no size limit

There is no single knob. Four independent layers can each kill a load:

| Layer | Symptom | Fix applied here |
|---|---|---|
| Ollama stall detector | `sched.go: timed out waiting for llama runner to start` in logs, always at exactly the configured duration | `OLLAMA_LOAD_TIMEOUT=0` (source-confirmed: zero/negative = infinite, default is 5m) |
| Ollama idle unload | First call after 5 min idle is slow/fails, not the first load itself | `OLLAMA_KEEP_ALIVE=-1` (negative = infinite, confirmed in `envconfig/config.go`) |
| Supervisor watchdog/healthcheck | Container gets restarted mid-load, `docker logs` shows the process killed, not erroring | **Not declared at all** in `config.yaml` — no `watchdog:`, no `image:` healthcheck. Don't add one. |
| Your HTTP client | `curl: (28) Operation timed out`, or a Python `requests`/`httpx` exception, or HA automation service-call timeout — while `docker logs` shows Ollama still happily loading | This is the one people miss. Ollama has no server-side answer for this — **you** control it, see below. |

## Client-side calls — always disable your own timeout

```bash
# unlimited
curl --max-time 0 http://<HA-IP>:11434/api/pull -d '{"name":"deepseek-r1:671b"}'

# generation on a model that's already loaded but huge (first-token latency
# on a 400B+ model can itself run past naive client defaults)
curl --max-time 0 http://<HA-IP>:11434/api/generate -d '{"model":"llama4:scout","prompt":"..."}'
```

Python: `ollama.Client(host=..., timeout=None)`. JS: pass no `AbortSignal` /
no fetch timeout. If you're calling this from a HA automation or a
`rest_command`, set `timeout:` generously there too (HA's default is 10s).

**Do not call this add-on's API through Supervisor ingress** for pulls or
generates — `ingress: false` is set deliberately in `config.yaml`. Call the
mapped port (`11434`) directly. Ingress adds another proxy hop with its own
timeout you don't control here.

## GPU devices

**NVIDIA (custom HAOS GPU build with `default-runtime: nvidia`):** works
with zero config as of 1.1.2. The image sets `NVIDIA_VISIBLE_DEVICES=all`
and `NVIDIA_DRIVER_CAPABILITIES=compute,utility`, which is what triggers
the nvidia-container-toolkit hook to inject `/dev/nvidia*` device nodes
and the host driver userspace (`libcuda.so`, `libnvidia-ml.so`,
`nvidia-smi`) into the container. Without those vars the hook does
nothing — the container gets no GPU even though the runtime is active,
which is exactly why the stock `ollama/ollama` image (which bakes these
in) detected a GPU while pre-1.1.2 builds of this app reported CPU-only.
The `devices:` list below is not involved in the NVIDIA path at all.

Verify after start: the log should show an `inference compute` line with
`library=cuda` and your card's VRAM instead of `id=cpu`. From the HAOS
host console: `docker exec addon_local_ollama_notimeout nvidia-smi`.

**Intel/AMD:** `config.yaml` passes these host device nodes:

```yaml
devices:
  - /dev/dri
  - /dev/kfd
```

(Current App schema takes plain host paths, not the old `src:dest:mode`
triplet — Supervisor maps existing ones into the container.)

The `gpu_devices` option feeds `ROCR_VISIBLE_DEVICES` and is **AMD-only,
numeric indices** (`0`, `0,1`). Leave it blank for NVIDIA — to pin
specific NVIDIA cards, use `extra_env` with
`{"CUDA_VISIBLE_DEVICES": "0"}`. GPU names like `4090 RTX` break
discovery outright; Ollama logs `user overrode visible devices` when this
happens.

## Install

1. Copy the `ollama_notimeout/` directory into `/addons/local/` over
   Samba/SSH for a local app — the folder itself, one level deep, so the
   path is `/addons/local/ollama_notimeout/config.yaml`. Or add the whole
   repo as a store repository (see the repo root README).
2. Settings → Apps → App Store → refresh (⋮ menu) → find it under Local →
   Install.
3. Check the log on first start for the `ollama --version` output to confirm
   the binary installed correctly for your arch.
4. Pull a model directly against the mapped port, not ingress:
   ```bash
   curl --max-time 0 http://<HA-IP>:11434/api/pull -d '{"name":"qwen3:30b"}'
   ```

## KV cache quantization & flash attention

If you've landed here from this error in the HA log:

```
llama-server process has terminated: llama_init_from_model: V cache quantization requires flash_attn (status code: 500)
```

that's a llama.cpp constraint, not a timeout: a quantized KV cache
(`OLLAMA_KV_CACHE_TYPE=q8_0`/`q4_0`) is only valid with flash attention
enabled. As of 1.1.3 both are first-class options and the run script
enforces the pairing — if a quantized cache type is set anywhere
(including via `extra_env`) while flash attention isn't explicitly on,
the app forces `OLLAMA_FLASH_ATTENTION=1` and logs a warning instead of
letting the model load 500.

`flash_attention_mode: auto` (the default) leaves the env var unset so Ollama
decides per model and hardware — FA is architecture-gated (embedding
models and certain archs are excluded), so a hard `on`/`off` is only for
overriding that judgment.

**Recommended for large models on a 24GB card** (e.g. gemma4:26b-class on
an RTX 4090): `flash_attention_mode: on` + `kv_cache_type: q8_0`. That roughly
halves KV-cache VRAM at negligible quality cost, which is often the
difference between full GPU offload and spilling to CPU at long contexts.
Set it in the app's Configuration tab rather than `extra_env` so the
compatibility guard and the UI stay authoritative.

## Storage & backups

`OLLAMA_MODELS=/share/ollama/models`, mapped via the `share` mount. This
puts model weights on the shared HA storage partition rather than the app's
private `/data`, so they survive app uninstall/reinstall and are reachable
over Samba.

Backup implications, stated precisely: HA backups treat "Share" as a single
component — there is no supported way to exclude just `share/ollama` from
it (the `backup_exclude` config key only filters the app's own `/data`,
which contains no models here, so it's deliberately absent from
`config.yaml`). If your backups balloon, deselect the **Share** folder in
your backup job/partial-backup selection, or relocate anything else you
keep in `/share` first. The app's own backup stays tiny either way since
`/data` holds only options.

## Shutdown behavior

s6-rc sends `ollama serve` a SIGTERM on stop and waits for it to exit —
there is no s6-side kill timeout configured. The real outer bound is
Supervisor's Docker stop timeout, raised from its 10s default via
`timeout: 120` in `config.yaml`. Note that a stop/restart discards loaded
models from memory regardless (weights on disk are untouched — they're
mmap'd read-only), so the cost of a restart is one model reload, not
corruption.

## If it still gets killed

Check `dmesg | grep -i oom` on the host first — the `finish` script logs
`killed by SIGKILL` for signal deaths, which is almost always the kernel
OOM killer: a real memory ceiling, not a timeout, and no timeout setting
will fix it.

## Troubleshooting: `CUDA error: PTX JIT compiler library not found`

CUDA error 221 (`CUDA_ERROR_JIT_COMPILER_NOT_FOUND`) during model
load/warmup, typically inside `ggml_cuda_kernel_can_use_pdl` →
`cudaFuncGetAttributes`. This is a **host image problem, not an app
problem**: libcuda needed to JIT-compile a PTX fatbin entry and could not
load the driver-side `libnvidia-ptxjitcompiler.so.<driver-version>`. The
nvidia-container-toolkit only injects driver libraries that exist (and
are ldconfig-discoverable) on the host — on custom HAOS GPU builds with a
curated NVIDIA userspace payload, ship `libnvidia-ptxjitcompiler` (plus
`libnvidia-nvvm`/`libnvidia-gpucomp` if present in the driver payload)
alongside `libcuda`/`libnvidia-ml`, version-matched to the kernel
modules, and regenerate the ldconfig cache. Verify injection afterwards:

```bash
docker exec addon_local_ollama_notimeout sh -c \
  'ls /usr/lib/x86_64-linux-gnu/ | grep -i ptxjit'
```

---

If this app saves you time: [buymeacoffee.com/sam3gp8](https://www.buymeacoffee.com/sam3gp8)
