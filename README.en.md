# strix-halo-llm-recipe

A **field-tested** configuration for running the
`halogen-qwen3.8-flash-next` model entirely on-device on an AMD Strix Halo
machine with Podman, and driving it from a coding agent with up to 4 parallel
sessions.

Not the vendor's documentation: it is the recipe we measured, with the numbers.
Every choice carries its reason and its cost, so you can adapt it to your
machine instead of copying it blind.

> Versione italiana: [README.md](README.md)

```
  opencode run -m halogen/halogen-qwen3.8-flash-next#xhigh
                     │
                     ▼  http://127.0.0.1:8731/v1
  ┌──────────────────────────────────────────────────────────────┐
  │ quadlet: halogen-flash.container (Podman, user unit)         │
  │  ctx 131072 · KV pool 524288 · 4 slots · vision · cache 96GiB │
  └──────────────────────────────────────────────────────────────┘
                     │
                     ▼  /models (read-only)
  ~/halogen-models  (~115 GB)
```

## What is here

| Path | What |
|---|---|
| `quadlet/halogen-flash.container` | Podman user unit, ready to copy |
| `opencode/halogen-provider.json` | `providers.halogen` block for OpenCode V2 |
| `tools/preflight.sh` | **run this first**: checks host, kernel, weights, RAM, disk |
| `tools/health.sh` | status, pool, cache, throughput, process memory |
| `tools/agent.sh` | launches a coding agent on the model, with timeout and log |
| `docs/requirements.md` | how to get the weights, and the two host prerequisites |
| `docs/sizing.md` | ctx and KV pool: the RAM arithmetic, and what to change |
| `docs/opencode.md` | thinking variants, token budget, timeouts |
| `docs/measured.md` | the numbers measured on this machine |
| `docs/troubleshooting.md` | the problems that cost us time |

## Quick start

Requirements: **native Linux** (not WSL2) with Podman ≥ 5, an AMD GPU with
`/dev/kfd` and `/dev/dri`, a kernel with AMD's gfx1151 fixes and
`CONFIG_HSA_AMD_SVM`, at least 96 GB of RAM, the weights already on disk.
[`docs/requirements.md`](docs/requirements.md) covers each one, and why
Windows and WSL2 cannot work at all.

```bash
# 0. are we ready? read-only, no side effects, names every blocker
bash tools/preflight.sh

# 1. weights (~115 GB): anywhere, even on another disk
#    hf download peonist-ai/halogen-qwen3.8-flash-next --local-dir ~/halogen-models

# 2. Podman user unit (never root)
mkdir -p ~/.config/containers/systemd
cp quadlet/halogen-flash.container ~/.config/containers/systemd/
#    open it and fix three things:
#      Volume=<weights>:/models:ro
#      Volume=<your home>/.cache/halogen-cache:/cache
#      ContainerName / HALOGEN_CTX if you sized down (docs/sizing.md)

# 3. prompt cache on disk (outside tmpfs/overlay), and keep it across logouts
mkdir -p ~/.cache/halogen-cache
sudo loginctl enable-linger "$USER"

# 4. start
systemctl --user daemon-reload
systemctl --user start halogen-flash
curl -s localhost:8731/health | jq '{status,model,context,slots}'

# 5. OpenCode: paste the block from opencode/halogen-provider.json
#    under "providers" in ~/.config/opencode/opencode.json, then:
opencode run -m halogen/halogen-qwen3.8-flash-next "hi"
```

Confirm everything with **`tools/health.sh`**.

## The five choices that make this config "optimised"

1. **`HALOGEN_CTX=131072` instead of the 262144 default.** The KV pool stays the
   official size: same performance, but 4 resident 128k conversations instead of
   2 of 256k. Real agentic sessions stay under 128k, and when they do not,
   compaction costs less than a cold prefill.
2. **`HALOGEN_KV_POOL_POSITIONS=524288` (4 × ctx).** Four sessions in flight;
   the fifth waits instead of failing. It is the number the vendor recommends
   with 4 slots.
3. **`HALOGEN_VISION_TOWER=1`.** This is what lets an agent read a screenshot
   and verify a UI or a site by itself. Costs a few GiB of VRAM.
4. **`HALOGEN_CACHE_DIR=/cache` on a real bind mount.** A 38k conversation
   resumes in 193 ms instead of a 24 s prefill. It must sit on a filesystem
   that accepts `O_DIRECT`: btrfs/ext4 yes, tmpfs and overlay no.
5. **`HALOGEN_MAX_TOKENS_DEFAULT=16384`.** Covers reasoning + tool call + answer
   of an ordinary agentic turn, for clients that do not send `max_tokens`.

And a sixth, learned the hard way: **`HALOGEN_CACHE_DISK_GIB=96`**. The 64 GiB
default filled up in 5 hours of agentic work (17 conversations of ~3.8 GiB) and
started evicting the sessions that were running.

## What NOT to enable without measuring

- `HALOGEN_INDEXER_BUDGET=4096` — slightly better retrieval, prefill +6.7%,
  replies not byte-identical. The 2048 default is fine.
- `HALOGEN_COMPOSABLE_CONTEXT=1` — faster compaction **but it refuses images**:
  if you need vision, leave it off.

## Numbers (measured, not estimated)

| | |
|---|---|
| Generation | ~58 tok/s (end-to-end mean with queueing: ~23 tok/s) |
| Prefill | ~1,060 tok/s |
| Warm conversation | 114 ms · 193 ms after a restart from disk |
| Cache hit, 5 agents for 5 hours | **93.8%** — 86M prompt tokens avoided |
| Server RAM | ~89.8 GiB of 121 (weights 62.9 + pool 14.4 + working 12.4) |

Details and reproduction commands in [`docs/measured.md`](docs/measured.md).

## Who already uses it

This is the configuration behind a real experiment: five complete software
projects (two sites, one full-stack web app, one GTK4 app and one .NET
solution) built by five agents in parallel on the local model, with independent
verification through tests and screenshots read back by the model itself.

## Licence

Recipe and scripts: MIT. Weights and server image remain their authors'
(`ghcr.io/peonist-ai/halogen-flash-server`) and are not included here.

"halogen" is a trademark of Peonist, LLC. This repository is an independent
deployment recipe, not affiliated with or endorsed by them; it is described as
a "halogen recipe" under their trademark policy, which permits descriptive use.
