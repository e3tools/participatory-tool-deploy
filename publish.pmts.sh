#!/bin/bash
set -e
 
echo "=== Triggering Publishing with Custom Parameters ==="
 
# Pass/override specific environment variables inline
IMPORT_EXTERNAL_SITE="true" \
IMPORT_EXTERNAL_DB="false" \
DOCKER_COMPOSE_FILE="docker-compose.pmts.yml" \
EXTERNAL_DB_CONTAINER="db" \
./_publish.sh

echo "Wrapper script completed successfully!"