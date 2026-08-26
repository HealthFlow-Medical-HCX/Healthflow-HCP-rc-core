#!/bin/bash
set -ex

echo "Building keycloak..."
docker build -t dockerhub/ndear-keycloak ./deps/keycloak

echo "Tagging and pushing images to fedis registry..."
REGISTRY="ext-gitlab.fedis.app:5050/healthcare/rosheta"

IMAGES=(
  "sunbird-rc-core"
  "sunbird-rc-claim-ms"
  "sunbird-rc-certificate-api"
  "sunbird-rc-certificate-signer"
  "sunbird-rc-notification-service"
  "ndear-keycloak"
)

for img in "${IMAGES[@]}"; do
  docker tag "dockerhub/${img}" "${REGISTRY}/${img}:latest"
  docker push "${REGISTRY}/${img}:latest"
done

echo "Successfully built and pushed all images!"
