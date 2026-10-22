# Documentation

## Options

| Option | Default | Notes |
|---|---|---|
| `keep_alive` | `-1` | Forever. Setting this to a positive duration re-introduces the reload-timeout problem on next call after idle. |
| `num_parallel` | `1` | Raise only if you have VRAM/RAM headroom for concurrent contexts. |
| `max_loaded_models` | `1` | Raise only with enough VRAM to hold multiple models at once — this is the #1 cause of OOM-kills (see finish script log). |
| `max_queue` | `512` | Requests beyond this are rejected outright rather than queued. |
| `context_length` | `4096` | Per-model override still possible via Modelfile `PARAMETER num_ctx`. |
| `flash_attention_mode` | `auto` | `auto` leaves `OLLAMA_FLASH_ATTENTION` unset so Ollama decides per model/hardware (FA is architecture-gated — embedding models and some archs are excluded). `on`/`off` force it. Forced back to on if a quantized `kv_cache_type` is set — llama.cpp hard-fails the load otherwise (`V cache quantization requires flash_attn`). |
| `kv_cache_type` | `default` | `default` = f16. `q8_0` ≈ halves KV-cache VRAM, negligible quality loss — the sensible pick for large models/long contexts on 24GB cards. `q4_0` ≈ quarters it, some quality loss. Applies globally to every model this server loads. |
| `gpu_devices` | `""` | **AMD/ROCm only** — numeric indices for `ROCR_VISIBLE_DEVICES` (e.g. `0`). Leave blank for NVIDIA: injection exposes all GPUs; pin NVIDIA devices via `extra_env` → `{"CUDA_VISIBLE_DEVICES": "0"}` instead. Names like `4090 RTX` break discovery (Ollama logs "user overrode visible devices"). |
| `extra_env` | `{}` | Free-form overrides, applied last, e.g. `{"CUDA_VISIBLE_DEVICES": "0"}`. |

See the main README.md for the full explanation of the four timeout layers
and why each is configured the way it is.

## API usage

Direct port, not ingress:

```bash
curl --max-time 0 http://<HA-IP>:11434/api/pull -d '{"name":"<model>"}'
curl --max-time 0 http://<HA-IP>:11434/api/generate -d '{"model":"<model>","prompt":"hello"}'
```

## Reading logs for OOM vs. timeout

```
Supervisor → ollama_notimeout → Log
```

A `killed by SIGKILL` line from the finish script = OOM kill, not a
timeout — reduce `max_loaded_models` or use a smaller quantization.
(Internally s6 reports a signal death as exit 256 + signal number, which
the finish script translates; you will not see the shell-style `137`.)
Anything else is a genuine crash; check the preceding `ollama serve`
output for the real error.

---

If this app saves you time: [buymeacoffee.com/sam3gp8](https://www.buymeacoffee.com/sam3gp8)
