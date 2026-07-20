#!/bin/bash
# Deploy script for Time of Life backend
# This script is called by the CI/CD pipeline (GitHub Actions).
# It builds the Docker image, pushes it to the registry, and deploys to the VM.
set -euo pipefail

# --- Configuration ---
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/antonkosenko/time-of-life-backend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
VM_HOST="${VM_HOST:-}"
VM_USER="${VM_USER:-antonkosenko}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/tmp/deploy_key}"

# --- Build and push ---
echo "==> Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f Dockerfile .

echo "==> Pushing to registry: ${IMAGE_NAME}:${IMAGE_TAG}"
docker push "${IMAGE_NAME}:${IMAGE_TAG}"

# --- Deploy to VM ---
if [ -n "$VM_HOST" ]; then
    echo "==> Deploying to VM: ${VM_HOST}"

    # Write SSH key
    if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
        echo "$SSH_PRIVATE_KEY" > "$SSH_KEY_PATH"
        chmod 600 "$SSH_KEY_PATH"
        SSH_OPTS="-i $SSH_KEY_PATH -o StrictHostKeyChecking=no"
    else
        SSH_OPTS="-o StrictHostKeyChecking=no"
    fi

    # Deploy on the VM
    ssh $SSH_OPTS "${VM_USER}@${VM_HOST}" bash -s << 'REMOTE'
        set -euo pipefail
        cd /opt/timeoflife

        # Pull the new image
        echo "==> Pulling new image"
        sudo docker compose pull backend

        # Recreate the backend container
        echo "==> Restarting backend"
        sudo docker compose up -d --no-deps backend

        # Clean up old images
        echo "==> Cleaning up old images"
        sudo docker image prune -f

        echo "==> Deployment complete"
REMOTE

    # Clean up SSH key
    rm -f "$SSH_KEY_PATH"
fi

echo "==> Done"
