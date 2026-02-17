# Use a lightweight Linux base
FROM ubuntu:24.04

# Install base dependencies, Python, and Node.js 22 (LTS)
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    python3 \
    python3-pip \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install AI CLIs via npm
# claude-code: https://github.com/anthropics/claude-code
# codex: https://github.com/openai/codex
# gemini-cli: https://github.com/google-gemini/gemini-cli
# opencode: https://github.com/anomalyco/opencode
# qwen-code: https://github.com/QwenLM/qwen-code
RUN npm install -g @qwen-code/qwen-code @google/gemini-cli @openai/codex @anthropic-ai/claude-code opencode-ai

# Setup CLI paths/symlinks
# Note: npm -g usually installs binaries to /usr/bin or /usr/local/bin depending on setup.
# On the official Node image it is /usr/local/bin, via nodesource/apt it is often /usr/bin.
# We create symlinks to ensure they are available at the expected /usr/local/bin paths.
RUN ln -sf $(which claude) /usr/local/bin/claude \
    && ln -sf $(which codex) /usr/local/bin/codex \
    && ln -sf $(which gemini) /usr/local/bin/gemini \
    && ln -sf $(which opencode) /usr/local/bin/opencode \
    && ln -sf $(which qwen) /usr/local/bin/qwen

# Configurable args for CLI locations
# These now point to the symlinks we created
ARG CLAUDE_PATH=/usr/local/bin/claude
ARG CODEX_PATH=/usr/local/bin/codex
ARG GEMINI_PATH=/usr/local/bin/gemini
ARG OPENCODE_PATH=/usr/local/bin/opencode
ARG QWEN_PATH=/usr/local/bin/qwen

# Set environment variables for the paths so they can be found easily
ENV CLAUDE_PATH=${CLAUDE_PATH}
ENV CODEX_PATH=${CODEX_PATH}
ENV GEMINI_PATH=${GEMINI_PATH}
ENV OPENCODE_PATH=${OPENCODE_PATH}
ENV QWEN_PATH=${QWEN_PATH}

# Add entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Default entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/bash"]
