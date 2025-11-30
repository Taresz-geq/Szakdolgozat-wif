#!/bin/bash
set -euo pipefail

# A pipeline-ból kapja az env változókat
PROJECT_ID="${PROJECT_ID:?Must set PROJECT_ID}"
REGION="${REGION:?Must set REGION}"
REPO="${REPO:?Must set REPO}"
IMAGE="${IMAGE:?Must set IMAGE}"
TAG="${TAG:-latest}"

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}"

echo "Building and pushing image: $IMAGE_URI"

docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE_URI" \
  --push .

echo "Done! Image pushed to $IMAGE_URI"
