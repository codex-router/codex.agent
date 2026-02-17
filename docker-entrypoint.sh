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

            # If the command is just 'codex' and arguments, we might need to handle
            # non-interactive execution if the tool requires a TTY.
            # However, for 'codex' specifically, passing the prompt as an argument usually works.
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

                        # Configure OpenCode LiteLLM provider (https://docs.litellm.com.cn/docs/tutorials/opencode_integration)
                        # Model keys should match LiteLLM model_name values.
                        if [ -n "$BASE_URL" ]; then
                                mkdir -p "${HOME}/.config/opencode"
                                export OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.json"

                                if [ -n "$MODEL" ]; then
                                        cat >"${OPENCODE_CONFIG}" <<EOF
{
    "$schema": "https://opencode.ac.cn/config.json",
    "provider": {
        "litellm": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LiteLLM",
            "options": {
                "baseURL": "${BASE_URL}"
            },
            "models": {
                "${MODEL}": {
                    "name": "${MODEL}"
                }
            }
        }
    }
}
EOF
                                else
                                        cat >"${OPENCODE_CONFIG}" <<EOF
{
    "$schema": "https://opencode.ac.cn/config.json",
    "provider": {
        "litellm": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LiteLLM",
            "options": {
                "baseURL": "${BASE_URL}"
            }
        }
    }
}
EOF
                                fi
                        fi
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
if [ "$1" = "codex" ] && [ ! -t 0 ]; then
    # When running without a TTY, 'codex' attempts to launch a TUI and fails.
    # The 'codex exec' subcommand is designed for non-interactive use.
    # We allow the user to pass 'codex' as the command, but transparently switch
    # to 'codex exec' if we detect there is no TTY.

    # We shift the first argument ('codex') and replace it with 'codex exec'
    shift
    # Automatically add --skip-git-repo-check to allow running in non-git directories (like container root)
    exec codex exec --skip-git-repo-check "$@"
elif [ "$1" = "opencode" ] && [ ! -t 0 ]; then
    # When running without a TTY (usually non-interactive mode), 'opencode' attempts to launch a TUI and treat arguments as folders.
    # We switch to 'opencode run' to execute a prompt non-interactively.
    shift

    # If a model wasn't explicitly provided, inject one from LITELLM_MODEL as litellm/<model>
    has_model_flag=false
    prev_arg=""
    for arg in "$@"; do
        if [ "$prev_arg" = "--model" ] || [ "$prev_arg" = "-m" ] || [ "$arg" = "--model" ] || [ "$arg" = "-m" ]; then
            has_model_flag=true
            break
        fi
        prev_arg="$arg"
    done

    if [ -n "$LITELLM_MODEL" ] && [ "$has_model_flag" = "false" ]; then
        exec opencode run --model "litellm/${LITELLM_MODEL}" "$@"
    fi

    exec opencode run "$@"
else
    exec "$@"
fi
