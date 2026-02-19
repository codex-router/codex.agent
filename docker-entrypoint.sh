#!/bin/bash
set -e

# AGENT_PROVIDER_NAME can be: claude, codex, gemini, opencode, qwen

if [ -n "$AGENT_PROVIDER_NAME" ]; then
    # Common variables from environment
    BASE_URL="${LITELLM_BASE_URL:-}"
    API_KEY="${LITELLM_API_KEY:-}"
    MODEL="${LITELLM_MODEL:-}"

    case "$AGENT_PROVIDER_NAME" in
        "claude")
            [ -n "$BASE_URL" ] && export ANTHROPIC_BASE_URL="$BASE_URL"
            [ -n "$API_KEY" ] && export ANTHROPIC_AUTH_TOKEN="$API_KEY"
            [ -n "$MODEL" ] && export ANTHROPIC_MODEL="$MODEL"
            ;;
        "codex")
            # Codex uses LITELLM_BASE_URL and LITELLM_API_KEY env vars
            [ -n "$BASE_URL" ] && export LITELLM_BASE_URL="$BASE_URL"
            # LITELLM_API_KEY is already set if passed, but being explicit does not hurt
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
    "\$schema": "https://opencode.ac.cn/config.json",
    "provider": {
        "litellm": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LiteLLM",
            "options": {
                "baseURL": "${BASE_URL}",
                "apiKey": "${API_KEY}"
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
    "\$schema": "https://opencode.ac.cn/config.json",
    "provider": {
        "litellm": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "LiteLLM",
            "options": {
                "baseURL": "${BASE_URL}",
                "apiKey": "${API_KEY}"
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
            echo "Warning: Unknown AGENT_PROVIDER_NAME: $AGENT_PROVIDER_NAME"
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
    # Use --json + --output-last-message, then suppress JSONL event output so only the
    # assistant's final message is printed to stdout.
    CODEX_LAST_MESSAGE_FILE="$(mktemp)"
    set +e
    codex exec --skip-git-repo-check --json --output-last-message "$CODEX_LAST_MESSAGE_FILE" "$@" >/dev/null
    CODEX_EXIT_CODE=$?
    set -e

    if [ -f "$CODEX_LAST_MESSAGE_FILE" ]; then
        cat "$CODEX_LAST_MESSAGE_FILE"
        rm -f "$CODEX_LAST_MESSAGE_FILE"
    fi

    exit "$CODEX_EXIT_CODE"
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

    OPENCODE_LAST_MESSAGE_FILE="$(mktemp)"
    OPENCODE_STDERR_FILE="$(mktemp)"
    set +e
    if [ -n "$LITELLM_MODEL" ] && [ "$has_model_flag" = "false" ]; then
        opencode run --model "litellm/${LITELLM_MODEL}" --print-logs false --output-file "$OPENCODE_LAST_MESSAGE_FILE" "$@" >/dev/null 2>"$OPENCODE_STDERR_FILE"
        OPENCODE_EXIT_CODE=$?
    else
        opencode run --print-logs false --output-file "$OPENCODE_LAST_MESSAGE_FILE" "$@" >/dev/null 2>"$OPENCODE_STDERR_FILE"
        OPENCODE_EXIT_CODE=$?
    fi
    set -e

    if [ -s "$OPENCODE_LAST_MESSAGE_FILE" ]; then
        cat "$OPENCODE_LAST_MESSAGE_FILE"
    else
        # Compatibility fallback for opencode versions that don't support
        # --output-file / --print-logs.
        OPENCODE_COMPAT_OUTPUT_FILE="$(mktemp)"
        set +e
        if [ -n "$LITELLM_MODEL" ] && [ "$has_model_flag" = "false" ]; then
            opencode run --model "litellm/${LITELLM_MODEL}" "$@" >"$OPENCODE_COMPAT_OUTPUT_FILE" 2>"$OPENCODE_STDERR_FILE"
            OPENCODE_EXIT_CODE=$?
        else
            opencode run "$@" >"$OPENCODE_COMPAT_OUTPUT_FILE" 2>"$OPENCODE_STDERR_FILE"
            OPENCODE_EXIT_CODE=$?
        fi
        set -e

        if [ -s "$OPENCODE_COMPAT_OUTPUT_FILE" ]; then
            cat "$OPENCODE_COMPAT_OUTPUT_FILE"
        elif [ -s "$OPENCODE_STDERR_FILE" ]; then
            cat "$OPENCODE_STDERR_FILE" >&2
        fi

        rm -f "$OPENCODE_COMPAT_OUTPUT_FILE"
    fi

    rm -f "$OPENCODE_LAST_MESSAGE_FILE" "$OPENCODE_STDERR_FILE"

    exit "$OPENCODE_EXIT_CODE"
else
    exec "$@"
fi
