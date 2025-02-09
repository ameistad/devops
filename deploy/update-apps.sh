#!/bin/bash
set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/app-config.json"
  exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file $CONFIG_FILE not found!"
  exit 1
fi

# Iterate over each app in the JSON config
for app in $(jq -c '.apps[]' "$CONFIG_FILE"); do
  # Parse JSON values
  name=$(echo "$app" | jq -r '.name')
  containerFile=$(echo "$app" | jq -r '.containerFile')
  port=$(echo "$app" | jq -r '.port')

  # Build environment flags (e.g. "-e KEY=VALUE")
  env_flags=""
  while IFS= read -r line; do
    env_flags+=" $line"
  done < <(echo "$app" | jq -r '.env | to_entries[] | "-e \(.key)=\(.value)"')

  # Assume the build context is the repository root (the parent directory of "containers")
  repo_dir=$(dirname "$(dirname "$containerFile")")

  echo "============================================"
  echo "Building image for: $name"
  echo "Dockerfile: $containerFile"
  echo "Context: $repo_dir"
  echo "Port: $port"
  echo "Environment flags: $env_flags"
  echo "============================================"

  # Build the image (forcing linux/amd64 if needed)
  docker build --platform linux/amd64 -f "$containerFile" -t "$name" "$repo_dir"

  # Remove any existing container with the same name
  if docker ps -a --format '{{.Names}}' | grep -w "$name" >/dev/null; then
    echo "Removing existing container $name"
    docker rm -f "$name"
  fi

  # Run the container.
  # We assume the container exposes port 80.
  echo "Running container $name on host port $port"
  docker run -d --name "$name" -p "${port}:80" $env_flags "$name"
done
