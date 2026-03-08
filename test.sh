#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="codex-agent:test"

echo "[1/2] Building Docker image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f Dockerfile .

echo "[2/2] Running smoke tests in container"

TEST_BASE_URL="https://litellm.example.com"
TEST_API_KEY="sk-test-key"
TEST_MODEL="gpt-5"

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

echo "- Verifying OpenClaw installation and seeded state"
docker run --rm \
    -e AGENT_PROVIDER_NAME="openclaw" \
    "$IMAGE_TAG" \
    bash -lc '
    set -e

    command -v openclaw >/dev/null
    openclaw --version >/dev/null
    command -v script >/dev/null
    command -v timeout >/dev/null
    [ -f /usr/local/share/codex-agent/openclaw.json ]

    [ -d /root/.openclaw/workspace ]
    python3 - <<"PY"
import json

with open("/root/.openclaw/openclaw.json", "r", encoding="utf-8") as fh:
    cfg = json.load(fh)

assert cfg["tools"]["profile"] == "full"
assert cfg["agents"]["defaults"]["workspace"] == "/root/.openclaw/workspace"
assert cfg["gateway"]["mode"] == "local"
assert cfg["gateway"]["port"] == 18789
assert cfg["gateway"]["bind"] == "lan"
assert cfg["gateway"]["auth"]["mode"] == "token"
assert bool(cfg["gateway"]["auth"]["token"])
assert cfg["commands"]["restart"] is True
PY

    [ -n "$OPENCLAW_PATH" ]
    [ -x "$OPENCLAW_PATH" ]
'

gateway_container="codex-agent-openclaw-gateway-$$"
gateway_token="openclaw-smoke-token"

cleanup_gateway_container() {
    docker rm -f "$gateway_container" >/dev/null 2>&1 || true
}
trap cleanup_gateway_container EXIT

mkdir -p /tmp/openclaw-test-no-bundled-plugins

docker run -d --rm \
    --name "$gateway_container" \
    -e AGENT_PROVIDER_NAME="openclaw" \
    -e OPENCLAW_STATE_DIR="/tmp/openclaw-test" \
    -e OPENCLAW_CONFIG_PATH="/tmp/openclaw-test/openclaw.json" \
    -e OPENCLAW_GATEWAY_MODE="local" \
    -e OPENCLAW_GATEWAY_PORT="18789" \
    -e OPENCLAW_GATEWAY_BIND="loopback" \
    -e OPENCLAW_GATEWAY_AUTH_MODE="token" \
    -e OPENCLAW_GATEWAY_TOKEN="$gateway_token" \
    -e OPENCLAW_GATEWAY_DISABLE_CONTROL_UI="1" \
    -e OPENCLAW_SKIP_CHANNELS="1" \
    -e OPENCLAW_SKIP_PROVIDERS="1" \
    -e OPENCLAW_SKIP_GMAIL_WATCHER="1" \
    -e OPENCLAW_SKIP_CRON="1" \
    -e OPENCLAW_SKIP_CANVAS_HOST="1" \
    -e OPENCLAW_SKIP_BROWSER_CONTROL_SERVER="1" \
    -e OPENCLAW_DISABLE_BONJOUR="1" \
    -e OPENCLAW_BUNDLED_PLUGINS_DIR="/tmp/openclaw-test-no-bundled-plugins" \
    "$IMAGE_TAG" \
    openclaw gateway --port 18789 >/dev/null

gateway_ready=false
for _ in $(seq 1 30); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$gateway_container" 2>/dev/null || echo false)" != "true" ]; then
        echo "Error: OpenClaw gateway exited during startup" >&2
        docker logs "$gateway_container" >&2 || true
        exit 1
    fi
    if docker exec "$gateway_container" python3 -c "import socket, sys; s=socket.socket(); s.settimeout(0.5); rc=s.connect_ex(('127.0.0.1', 18789)); s.close(); sys.exit(0 if rc == 0 else 1)"; then
        gateway_ready=true
        break
    fi
    sleep 1
done

if [ "$gateway_ready" != "true" ]; then
    echo "Error: OpenClaw gateway did not start" >&2
    docker exec "$gateway_container" openclaw gateway status >&2 || true
    docker logs "$gateway_container" >&2 || true
    exit 1
fi

docker exec "$gateway_container" openclaw gateway status >/dev/null

set +e
docker exec "$gateway_container" bash -lc "timeout 12s script -qec 'openclaw tui --url ws://127.0.0.1:18789 --token $gateway_token --message hello --history-limit 5' /tmp/openclaw-tui.log >/dev/null 2>&1"
tui_exit=$?
set -e

if [ "$tui_exit" -ne 0 ] && [ "$tui_exit" -ne 124 ]; then
    echo "Error: OpenClaw TUI exited unexpectedly with code $tui_exit" >&2
    docker exec "$gateway_container" cat /tmp/openclaw-tui.log >&2 || true
    docker logs "$gateway_container" >&2 || true
    exit 1
fi

docker exec "$gateway_container" grep -a -q "hello" /tmp/openclaw-tui.log

cleanup_gateway_container
trap - EXIT

# 2. Provider checks
# Codex -> LITELLM_BASE_URL, LITELLM_API_KEY (and config file check inside helper)
run_provider_test "codex" "LITELLM_BASE_URL LITELLM_API_KEY"

# Opencode -> OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_MODEL
run_provider_test "opencode" "OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL"

# Qwen -> OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_MODEL
run_provider_test "qwen" "OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL"

# Kimi -> KIMI_BASE_URL, KIMI_API_KEY, KIMI_MODEL_NAME
run_provider_test "kimi" "KIMI_BASE_URL KIMI_API_KEY KIMI_MODEL_NAME"

echo "All Docker smoke tests passed."
