FROM debian:bookworm-slim

ARG BUILD_VERSION="0.0.0"
ARG BUILD_ARCH
ARG OLLAMA_VERSION="0.40.12"
ARG S6_OVERLAY_VERSION="3.2.1.0"

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Ollama (No-Timeout GPU)" \
    org.opencontainers.image.description="Local Ollama server tuned to never time out loading/unloading models regardless of size, with GPU device passthrough for custom HAOS builds." \
    org.opencontainers.image.source="https://github.com/sam3gp8/Ollama-HA-GPU"

# --- Base image note ---
# Deliberately NOT ghcr.io/home-assistant/base (Alpine/musl). Ollama's
# official Linux release binary is glibc-linked (interpreter
# /lib64/ld-linux-x86-64.so.2), and it bundles hundreds of MB of CUDA/ROCm
# runtime .so files that are themselves glibc binaries — not just the
# loader path but the full libc/libstdc++ ABI needs to match. Patching
# that onto Alpine via gcompat is explicitly called out as unreliable for
# production by Alpine's own wiki. Debian sidesteps the whole problem.
# Since Supervisor 2026.04.0 the App builder no longer requires the HA
# base image, so this is fully supported.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        xz-utils \
        zstd \
        jq \
    && rm -rf /var/lib/apt/lists/*

# --- s6-overlay v3 (manual install, since we've left the HA base image) ---
RUN set -eux; \
    case "${BUILD_ARCH}" in \
        amd64) S6ARCH="x86_64" ;; \
        aarch64) S6ARCH="aarch64" ;; \
        *) echo "unsupported arch: ${BUILD_ARCH}" && exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

# S6_KEEP_ENV=1 is load-bearing: without it, s6-overlay v3 strips the
# container environment from services, and the run script would not see
# the OLLAMA_* vars set below (they'd only be reachable via with-contenv,
# which is execline, not bash).
#
# Shutdown grace: s6-rc longruns with no `timeout-kill` file wait
# indefinitely after SIGTERM — the real outer bound is Supervisor's
# Docker stop timeout, set via `timeout:` in config.yaml (default 10s,
# raised to 120 there). S6_SERVICES_GRACETIME would NOT help: it only
# applies to legacy /etc/services.d services, which this image doesn't use.
ENV S6_KEEP_ENV=1

# --- Ollama (glibc-native now, so no interpreter mismatch) ---
RUN set -eux; \
    case "${BUILD_ARCH}" in \
        amd64) OARCH="amd64" ;; \
        aarch64) OARCH="arm64" ;; \
        *) echo "unsupported arch: ${BUILD_ARCH}" && exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${OARCH}.tar.zst" \
        -o /tmp/ollama.tar.zst; \
    zstd -d -c /tmp/ollama.tar.zst | tar -x -C /usr; \
    rm /tmp/ollama.tar.zst; \
    /usr/bin/ollama --version

# --- NVIDIA container-runtime injection trigger ---
# On HAOS GPU builds with default-runtime=nvidia baked into daemon.json,
# the nvidia-container-toolkit hook only injects /dev/nvidia* and the
# host driver userspace (libcuda.so, libnvidia-ml.so, nvidia-smi) when
# the container declares NVIDIA_VISIBLE_DEVICES. The official
# ollama/ollama image sets exactly these two vars — their absence here is
# why that image saw the GPU and this one reported CPU-only. Harmless on
# hosts without the nvidia runtime (plain env vars nothing reads).
# compute = CUDA; utility = NVML/nvidia-smi (Ollama's discovery path).
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# --- Timeout-relevant environment ---
# OLLAMA_KEEP_ALIVE=-1  : never unload a loaded model on idle; the
#                         reload-on-next-request is what usually blows a
#                         client's HTTP timeout on big models, not the
#                         initial load.
# OLLAMA_LOAD_TIMEOUT=0 : zero/negative = infinite stall detection during
#                         model load (source-confirmed, envconfig/config.go).
ENV OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_ORIGINS=* \
    OLLAMA_KEEP_ALIVE=-1 \
    OLLAMA_MAX_QUEUE=512 \
    OLLAMA_LOAD_TIMEOUT=0 \
    OLLAMA_MODELS=/share/ollama/models \
    OLLAMA_TMPDIR=/share/ollama/tmp

COPY rootfs /

RUN chmod a+x \
        /etc/s6-overlay/s6-rc.d/ollama/run \
        /etc/s6-overlay/s6-rc.d/ollama/finish

ENTRYPOINT ["/init"]
