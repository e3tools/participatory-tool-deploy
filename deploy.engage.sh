#!/bin/bash
set -e
 
echo "=== Triggering Production Deployment with Custom Parameters ==="

# # Pass/override specific environment variables inline
# IMPORT_EXTERNAL_SITE="true" \
# DOCKER_COMPOSE_FILE="docker-compose.engage.yml" \ 
# # IMPORT_EXTERNAL_SITE="${IMPORT_EXTERNAL_SITE:-false}" \
# ENGAGE_PROJECT_NAME="engage-participatory-tool" \
# ./deploy.sh

# Pass/override specific environment variables inline
IMPORT_EXTERNAL_SITE="true" \
IMPORT_EXTERNAL_DB="false" \
DOCKER_COMPOSE_FILE="docker-compose.engage.yml" \
EXTERNAL_DB_CONTAINER="db" \
./_deploy.sh

echo "Wrapper script completed successfully!"