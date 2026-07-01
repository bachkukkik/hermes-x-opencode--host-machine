# 03 — Model Discovery

## What

Model discovery queries the LiteLLM proxy's `/v1/models` endpoint, filters non-chat models through a regex skip list, deduplicates case-insensitively, and provides the resulting list to downstream config generators.

## Why

- The LiteLLM proxy aggregates models from multiple backends (OpenAI, Anthropic, GLM, DeepSeek) into a single endpoint. The raw list includes embedding, TTS, image, and moderation models that are irrelevant for chat-based agents.
- Without filtering, OpenCode and Hermes configs would present non-functional models to the user. The filter pipeline mirrors exactly the Docker reference to maintain parity.
- Fallback to a default model ensures the pipeline produces usable output even when the proxy is unreachable.

## How

### Discovery pipeline

```
LiteLLM /v1/models  ──►  auth via api_key  ──►  JSON parse  ──►  extract .data[].id
                                                                         │
                                                                         ▼
                                                                regex filter pipeline
                                                                         │
                                                                         ▼
                                                                case-insensitive dedup
                                                                         │
                                                                         ▼
                                                                fallback check (EC1)
                                                                         │
                                                                         ▼
                                                                DISCOVERED_MODELS
```

### Authentication (EC2)

The LiteLLM API key is read **in-process via Python** — never exposed as a shell variable:

```python
# Inside discover_models() python3 heredoc
with open(config_path) as f:
    data = yaml.safe_load(f.read()) or {}
m = data.get("model") or {}
api_key = m.get("api_key", "").strip()
# Fallback: custom_providers[].api_key
if not api_key:
    for cp in (data.get("custom_providers") or []):
        if isinstance(cp, dict) and cp["api_key"].strip():
            api_key = cp["api_key"].strip()
            break

# HTTP request happens inside the same Python process
req = urllib.request.Request(url, headers={"Authorization": "Bearer " + api_key})
with urllib.request.urlopen(req, timeout=15) as resp:
    data = json.load(resp)
```

The `api_key` string never passes through `bash` variable interpolation, avoiding Hermes secret-redaction that would mangle the key into `[REDACTED]`.

### Filter pipeline

The filter regex list drops every known non-chat model category:

| Pattern | Category dropped |
|---------|-----------------|
| `embed` | Embedding models |
| `whisper`, `tts`, `audio` | Speech/audio |
| `dall[\-\-]?e`, `image`, `stable`, `midjourney`, `flux`, `replicate`, `/sd/`, `mj`, `resolution` | Image generation |
| `sora` | Video generation |
| `realtime` | Real-time streaming |
| `transcrib`, `moderat` | Transcription, moderation |
| `codegen` | Code generation (non-chat) |
| `babbage`, `davinci`, `curie`, `ada`, `text-` | Legacy completion models |
| `cli-proxy-api` | Internal proxy routing |
| `/\*$` | Wildcard model entries |

After filtering, models are deduplicated **case-insensitively** — `zai/GLM-5.2` and `zai/glm-5.2` resolve to the same entry (first-seen case form wins).

### Fallback logic (EC1)

```python
if not filtered:
    filtered = [default_model]                    # empty list → seed default
elif not any(m.lower() == default_model.lower() for m in filtered):
    filtered.insert(0, default_model)             # default not present → prepend
```

The default model (`zai/glm-5.2`) is always present in the final list, either as the sole entry (when LiteLLM is unreachable) or prepended to the discovered list.

### Output format

Discovered models are written to `staging/discovered-models.txt` as a newline-separated list and stored in the shell variable `DISCOVERED_MODELS`. Downstream generators read from the file to avoid stdin/heredoc conflicts (the `python3 -` heredoc consumes stdin, so piped data cannot be received simultaneously).

## Verification

```bash
# Check LiteLLM proxy health
curl -s http://localhost:4000/health

# Query models endpoint directly (with auth)
API_KEY=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('$HOME/.hermes/config.yaml'))
print(cfg.get('model',{}).get('api_key',''))
")
curl -s -H "Authorization: Bearer $API_KEY" http://localhost:4000/v1/models | python3 -m json.tool | grep '"id"'

# Run discovery and check output
cd ~/.hermes/host-config-gen
bash generate.sh
echo "Model count: $(wc -l < staging/discovered-models.txt)"
head -10 staging/discovered-models.txt

# Verify no non-chat models leaked
grep -iE 'embed|whisper|tts|dalle|sora|moderat' staging/discovered-models.txt && echo "LEAK DETECTED" || echo "Filter clean"

# Verify default model is present
grep -qi 'zai/glm-5.2' staging/discovered-models.txt && echo "Default model present" || echo "Default model MISSING"

# Verify no duplicates (case-insensitive)
sort -f staging/discovered-models.txt | uniq -di | grep . && echo "DUPLICATES FOUND" || echo "No duplicates"
```

## What Works

- LiteLLM `/v1/models` is queried with proper Bearer auth read in-process from `config.yaml`
- Non-chat model categories are filtered by a comprehensive regex skip list
- Case-insensitive deduplication prevents duplicate model entries
- Default model (`zai/glm-5.2`) is guaranteed present in the output
- API key never passes through shell variable interpolation (EC2)
- Output is written to a file, avoiding stdin/heredoc conflicts

## What Fails

- **EC1 — LiteLLM unreachable:** If the proxy is down or `OPENAI_BASE_URL` is misconfigured, the discovery returns `OPENAI_DEFAULT_MODEL` as the sole entry. All other models are unavailable.
- **Empty model list:** If LiteLLM responds successfully but `/v1/models` returns an empty `data` array (no models configured), the fallback activates — same as EC1.
- **No api_key in config:** If `config.yaml` has no `model.api_key` and no `custom_providers[].api_key`, the request is sent without an `Authorization` header. LiteLLM may reject it or return a limited model list.

## Resolution

- **EC1 — LiteLLM unreachable:** Verify the proxy is running (`curl http://localhost:4000/health`). Check `OPENAI_BASE_URL` in the environment. For remote proxies, ensure network connectivity and port access.
- **Empty model list:** Configure models in the LiteLLM proxy. The generator falls back to `OPENAI_DEFAULT_MODEL` transparently; basic functionality survives.
- **No api_key in config:** Add `model.api_key` to `~/.hermes/config.yaml`. Without authentication, LiteLLM may return a restricted subset or reject the request entirely.

### Quantized GGUF context-length pin (PR #66 / CA-31-A)

The `resolve_ctx_len()` function uses a longest-match-first pin table. A critical ordering rule: **specific quantized pins must appear BEFORE family wildcards** so the most-specific match wins first.

For example, `*qwen3.6-27b*q4*` (quantized GGUF, real ctx 262,144) sits before `*qwen3.6*` (family wildcard, 1,048,576). Without this ordering, a quantized model like `llama_cpp/qwen3.6-27b-q4_k_m` would incorrectly resolve to the family's 1M window instead of its true 262K limit.

This is the **first-match-wins** principle applied at the pattern level — the same rule that keeps `*gpt-5.4*` from being swallowed by `*gpt-5*`.

## Verdict

The discovery pipeline faithfully replicates the Docker reference while adding the critical in-process key safety guarantee. The 15-pattern filter list covers all known non-chat model categories from major providers. The fallback to `OPENAI_DEFAULT_MODEL` ensures the pipeline never produces an empty model list, even under total proxy failure.
