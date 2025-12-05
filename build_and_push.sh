#!/bin/bash
set -e

IMAGE="registry.digitalocean.com/saturnci/nova-worker-agent"
TAG="${1:-latest}"

echo "==> Logging into DigitalOcean registry..."
doctl registry login

echo "==> Building $IMAGE:$TAG for linux/amd64..."
docker build --platform linux/amd64 -t "$IMAGE:$TAG" .

echo "==> Pushing $IMAGE:$TAG..."
docker push "$IMAGE:$TAG"

echo "==> Done!"
