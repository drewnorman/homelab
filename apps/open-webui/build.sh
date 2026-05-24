#!/bin/bash
# Builds and pushes the Open WebUI wrapper image to Artifact Registry.
# Run this after tofu apply has created the Artifact Registry repository.
#
# Usage: bash apps/open-webui/build.sh
set -euo pipefail

IMAGE_URI=$(tofu output -raw claude_troubleshooter_image_uri)
REGISTRY=$(echo "$IMAGE_URI" | cut -d/ -f1)

echo "Authenticating podman with ${REGISTRY}..."
gcloud auth print-access-token | podman login -u oauth2accesstoken --password-stdin "$REGISTRY"

echo "Building image..."
podman build --platform linux/amd64 -t "$IMAGE_URI" "$(dirname "$0")"

echo "Pushing ${IMAGE_URI}..."
podman push "$IMAGE_URI"

echo ""
echo "Done. Update claude_troubleshooter_image in terraform.tfvars:"
echo "  claude_troubleshooter_image = \"${IMAGE_URI}\""
echo "Then run: tofu apply"
