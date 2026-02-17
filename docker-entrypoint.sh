#!/bin/bash
set -e

# CLI_PROVIDER_NAME can be: claude, codex, gemini, opencode, qwen

if [ -n "$CLI_PROVIDER_NAME" ]; then
    echo "Configuring environment for CLI provider: $CLI_PROVIDER_NAME"

    # Common variables from environment
    BASE_URL="${LITELLM_BASE_URL:-}"
    API_KEY="${LITELLM_API_KEY:-}"
    MODEL="${LITELLM_MODEL:-}"

    case "$CLI_PROVIDER_NAME" in
        "claude")
            [ -n "$BASE_URL" ] && export ANTHROPIC_BASE_URL="$BASE_URL"
            [ -n "$API_KEY" ] && export ANTHROPIC_AUTH_TOKEN="$API_KEY"
            [ -n "$MODEL" ] && export ANTHROPIC_MODEL="$MODEL"
            ;;
        "codex")
            # Codex uses LITELLM_API_BASE and LITELLM_API_KEY env vars
            [ -n "$BASE_URL" ] && export LITELLM_API_BASE="$BASE_URL"
            # LITELLM_API_KEY is already set if passed, but being explicit doesn't hurt
            [ -n "$API_KEY" ] && export LITELLM_API_KEY="$API_KEY"

            # Generate config file if needed
            if [ -n "$MODEL" ] || [ -n "$BASE_URL" ] || [ -n "$API_KEY" ]; then
                mkdir -p "${HOME}/.codex"
                cat >"${HOME}/.codex/config.toml" <<EOF
model = "${MODEL}"
model_provider = "litellm"

[model_providers.litellm]
name = "LiteLLM"
base_url = "${BASE_URL}"
env_key = "LITELLM_API_KEY"
wire_api = "responses"
EOF
            fi
            ;;
        "gemini")
            [ -n "$BASE_URL" ] && export GOOGLE_GEMINI_BASE_URL="$BASE_URL"
            [ -n "$API_KEY" ] && export GEMINI_API_KEY="$API_KEY"
            [ -n "$MODEL" ] && export GEMINI_MODEL="$MODEL"
            ;;
        "opencode")
            [ -n "$BASE_URL" ] && export OPENAI_BASE_URL="$BASE_URL"
            [ -n "$API_KEY" ] && export OPENAI_API_KEY="$API_KEY"
            [ -n "$MODEL" ] && export OPENAI_MODEL="$MODEL"
            ;;
        "qwen")
            [ -n "$BASE_URL" ] && export OPENAI_BASE_URL="$BASE_URL"
            [ -n "$API_KEY" ] && export OPENAI_API_KEY="$API_KEY"
            [ -n "$MODEL" ] && export OPENAI_MODEL="$MODEL"
            ;;
        *)
            echo "Warning: Unknown CLI_PROVIDER_NAME: $CLI_PROVIDER_NAME"
            ;;
    esac
fi

# Execute the passed command
exec "$@"
