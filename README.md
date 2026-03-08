# codex.agent

Docker environment for the Codex Gerrit plugin agents. This image bundles all supported AI agents into a single container, ready to be used by `codex.serve`.

## Included agents

- **Codex CLI** (`codex`): Installed via `@openai/codex`.
- **OpenClaw** (`openclaw`): Installed via `openclaw@latest`.
- **OpenCode** (`opencode`): Installed via `opencode-ai`.
- **Qwen Code** (`qwen`): Installed via `@qwen-code/qwen-code`.
- **Kimi Code CLI** (`kimi`): Installed via `kimi-cli`.

## Requirements

- Docker installed.

## Build

Build the image from the `codex.agent` directory:

```bash
./build.sh
```

## Test

Run the Docker smoke test from the `codex.agent` directory:

```bash
./test.sh
```

The test script builds a temporary image (`codex-agent:test`) and verifies:

- Base image is Ubuntu.
- All required agent binaries are available and return `--version`.
- `openclaw` seeds a default `~/.openclaw` state directory for container-local runs.
- Per-agent provider settings are validated with explicit test values for base URL, API key, and model:
  - `codex`: `LITELLM_BASE_URL`, `LITELLM_API_KEY`, and `~/.codex/config.toml` model/provider config
	- `opencode`: `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL`
	- `qwen`: `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL`
  - `kimi`: `KIMI_BASE_URL`, `KIMI_API_KEY`, `KIMI_MODEL_NAME`
- `CODEX_PATH`, `OPENCLAW_PATH`, `OPENCODE_PATH`, `QWEN_PATH`, and `KIMI_PATH` are set to executable paths.

## Usage

This image is designed to work with `codex.serve`.

1.  Build the image as shown above.
2.  Configure `codex.serve` to use this image by setting the `CODEX_AGENT_IMAGE` environment variable.

```bash
export CODEX_AGENT_IMAGE=craftslab/codex-agent:latest
python codex.serve/codex_serve.py
```

`codex.serve` will then spin up this container for every agent request, passing necessary environment variables (like API keys) and streaming the output back to the plugin.

### Manual Usage

You can also run the container interactively for testing:

```bash
docker run -it --rm craftslab/codex-agent:latest bash
codex --version
openclaw --version
opencode --version
qwen --version
kimi --version
```

OpenClaw's upstream install flow normally uses `openclaw onboard --install-daemon` to register a user service. This image adapts that flow for containers by preinstalling the CLI, exposing `openclaw`, and seeding `~/.openclaw/openclaw.json` from the bundled [codex.agent/openclaw.json](codex.agent/openclaw.json) instead of attempting to run `systemd` inside the container. That bundled config includes the default workspace, `tools.profile = "full"`, gateway token auth, and the local gateway settings used by this image.

### Configuration via Environment Variables

The image supports automatic configuration of the agents using a standard set of environment variables. This is handled by the entrypoint script.

- `AGENT_PROVIDER_NAME`: The name of the agent to configure (`codex`, `openclaw`, `opencode`, `qwen`, `kimi`).
- `LITELLM_BASE_URL`: The base URL for the API provider.
- `LITELLM_API_KEY`: The API key for the provider.
- `LITELLM_MODEL`: The model name to use.

For `openclaw`, the image also exports:

- `OPENCLAW_PATH`: Executable path for the CLI.
- `OPENCLAW_STATE_DIR`: Container-local state directory (default `/root/.openclaw`).
- `OPENCLAW_CONFIG_PATH`: Default config file path.
- `OPENCLAW_CONFIG_TEMPLATE`: Seed config template path (default `/usr/local/share/codex-agent/openclaw.json`).
- `OPENCLAW_TOOLS_PROFILE`: Default tools profile for generated config (`full`).
- `OPENCLAW_GATEWAY_PORT`: Default gateway port (`18789`).
- `OPENCLAW_GATEWAY_MODE`: Default gateway mode (`local`).
- `OPENCLAW_GATEWAY_BIND`: Default gateway bind (`lan`).

Example:

```bash
docker run --rm \
  -e AGENT_PROVIDER_NAME=codex \
  -e LITELLM_BASE_URL="https://your-litellm-endpoint" \
  -e LITELLM_API_KEY="sk-..." \
  -e LITELLM_MODEL="gpt-5" \
  craftslab/codex-agent:latest \
  codex "Hello, world!"
```
