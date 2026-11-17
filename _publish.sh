#!/bin/bash
set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration: Replace with your actual Docker Hub username/namespace
DOCKER_HUB_USER="${DOCKER_HUB_USER:-stevenyaga}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose-with-engage-app.yml}"
 
echo "=== 1. Logging into Docker Hub ==="
docker login

echo "=== 2. Building  Docker Images Locally ==="
docker compose -f ${DOCKER_COMPOSE_FILE} build --no-cache

echo "=== 3. Tagging Images for Docker Hub ==="
# This can be optional since docker compose file already contains the image name
# docker tag frappe-backend:latest ${DOCKER_HUB_USER}/frappe-backend:latest
# docker tag nyeri-react:latest ${DOCKER_HUB_USER}/nyeri-react:latest
# docker tag muranga-react:latest ${DOCKER_HUB_USER}/muranga-react:latest
# docker tag nyeri-engage-app:latest ${DOCKER_HUB_USER}/nyeri-engage-app:latest

echo "=== 4. Pushing Images to Docker Hub ==="
docker compose -f ${DOCKER_COMPOSE_FILE} push 

echo "=== Publishing Completed Successfully! ==="