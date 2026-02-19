#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="codex-agent:test"

echo "[1/2] Building Docker image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f Dockerfile .

echo "[2/2] Running smoke tests in container"

TEST_BASE_URL="https://litellm.example.com"
TEST_API_KEY="sk-test-key"
TEST_MODEL="gemini-2.5-pro"

run_provider_test() {
    local provider="$1"
    local expected_vars="$2"

    echo "- Testing provider configuration: $provider ($expected_vars)"

    # We pass the check logic as a heredoc script to avoid complex escaping
    docker run --rm \
        -e AGENT_PROVIDER_NAME="$provider" \
        -e LITELLM_BASE_URL="${TEST_BASE_URL}" \
        -e LITELLM_API_KEY="${TEST_API_KEY}" \
        -e LITELLM_MODEL="${TEST_MODEL}" \
        "${IMAGE_TAG}" \
        bash -c "
            set -e

            check_var() {
                local name=\"\$1\"
                local val=\"\${!name}\"
                if [ -z \"\$val\" ]; then
                    echo \"Error: Expected env var \$name to be set inside container for provider $provider\"
                    exit 1
                fi
                echo \"  OK: \$name is set\"
            }

            echo '  > Verifying agent binary availability...'
            if ! command -v $provider >/dev/null; then
               echo 'Error: binary $provider not found'
               exit 1
            fi

            echo '  > Verifying mapped environment variables...'
            for v in $expected_vars; do
                check_var \"\$v\"
            done

            if [ \"$provider\" = \"codex\" ]; then
                echo '  > Verifying codex config file...'
                if [ ! -f ~/.codex/config.toml ]; then
                    echo 'Error: ~/.codex/config.toml missing'
                    exit 1
                fi
                if ! grep -q \"${TEST_MODEL}\" ~/.codex/config.toml; then
                     echo 'Error: ~/.codex/config.toml content mismatch'
                     cat ~/.codex/config.toml
                     exit 1
                fi
            fi
            echo '  > Provider test passed'
        "
}

# 1. Base image check
echo "- Verifying base image (Ubuntu)"
docker run --rm "$IMAGE_TAG" bash -c 'grep -qi "^ID=ubuntu" /etc/os-release'

# 2. Provider checks
# Claude -> ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL
run_provider_test "claude" "ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL"

# Codex -> LITELLM_BASE_URL, LITELLM_API_KEY (and config file check inside helper)
run_provider_test "codex" "LITELLM_BASE_URL LITELLM_API_KEY"

# Gemini -> GOOGLE_GEMINI_BASE_URL, GEMINI_API_KEY, GEMINI_MODEL
run_provider_test "gemini" "GOOGLE_GEMINI_BASE_URL GEMINI_API_KEY GEMINI_MODEL"

# Opencode -> OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_MODEL
run_provider_test "opencode" "OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL"

# Qwen -> OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_MODEL
run_provider_test "qwen" "OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL"

echo "All Docker smoke tests passed."
