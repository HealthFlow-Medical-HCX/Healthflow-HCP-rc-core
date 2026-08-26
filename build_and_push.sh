#!/bin/bash
set -ex

# 1. Compile Java projects and prepare target folders using a Maven Docker container
echo "Compiling Java projects in Docker container..."
docker run --rm -v "$(pwd):/workspace" -w /workspace maven:3.8.7-eclipse-temurin-8 bash -c '
set -e
sh configure-dependencies.sh

echo "Building java/registry..."
cd /workspace/java && ./mvnw clean install -DskipTests

echo "Building java/claim..."
cd /workspace/java/claim && ../mvnw clean install -DskipTests

echo "Building keycloak-mobile-number-login-spi..."
cd /workspace/deps/keycloak-mobile-number-login-spi && ./mvnw clean install -DskipTests
mkdir -p ../keycloak/providers && cp target/keycloak-mobile-number-login-spi-1.0-SNAPSHOT.jar ../keycloak/providers

echo "Preparing sunbird-rc-core target..."
cd /workspace
mkdir -p target
cd target
rm -rf *
jar xvf ../java/registry/target/registry.jar
cp ../Dockerfile ./
'

# 2. Build all Docker images natively on the host
echo "Building Docker images..."
docker build -t dockerhub/sunbird-rc-core ./target
docker build -t dockerhub/sunbird-rc-claim-ms ./java/claim
make -C services/certificate-api docker
make -C services/certificate-signer docker
make -C services/notification-service docker
docker build -t dockerhub/ndear-keycloak ./deps/keycloak

# 3. Tag and push to fedis registry
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
