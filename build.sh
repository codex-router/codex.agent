#!/bin/bash

# Exit on error
set -e

# Change to the directory where the script is located
cd "$(dirname "$0")"

echo "Building craftslab/codex-agent:latest Docker image..."
docker build -t craftslab/codex-agent:latest .

