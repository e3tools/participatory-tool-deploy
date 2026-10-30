#!/bin/bash
set -e

# # Load environment variables from .env if it exists
# if [ -f .env ]; then
#     set -a
#     source .env
#     set +a
# fi

# ==========================================
# 1. Smart Environment & .env Configuration
# ==========================================
# Load .env file only for variables not already set in the environment 
# (This allows inline environment variable overrides to take precedence)
if [ -f .env ]; then
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] || [ -z "$key" ] && continue
        # Clean up whitespace and quotes
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        
        # Only set from .env if not already passed inline in the environment
        if [ -z "${!key:-}" ]; then
            export "$key"="$value"
        fi
    done < .env
fi

# Set defaults if neither inline override nor .env provided them 
DOCKER_HUB_USER="${DOCKER_HUB_USER:-stevenyaga}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-admin}"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose-with-engage-app.yml}"
PROJECT_NAME="${ENGAGE_PROJECT_NAME:-}"
IMPORT_EXTERNAL_SITE="${IMPORT_EXTERNAL_SITE:-false}"

# Example: Dynamically resolve the volume mount point via Docker daemon
EXTERNAL_VOLUME_NAME="${EXTERNAL_VOLUME_NAME}"
EXTERNAL_SITES_DIR=$(docker volume inspect "$EXTERNAL_VOLUME_NAME" --format '{{ .Mountpoint }}' 2>/dev/null || echo "")
# EXTERNAL_SITES_DIR="${EXTERNAL_SITES_DIR:-}"

echo "EXTERNAL_SITES_DIR is: ${EXTERNAL_SITES_DIR}"
 
echo "=== 1. Stopping Old and Pulling Latest Images from Docker Hub ===" 
docker compose -f ${DOCKER_COMPOSE_FILE} pull

echo "=== 2. Restarting Containers ==="
docker compose -f ${DOCKER_COMPOSE_FILE} up -d

echo "=== 3. Waiting for MariaDB to be Ready ==="
echo "Polling database connection..."
until docker compose -f ${DOCKER_COMPOSE_FILE} exec -T db mysqladmin ping -h localhost -u root -p"${DB_ROOT_PASSWORD}" --silent; do
    echo "Database is starting up, waiting 3 seconds..."
    sleep 3
done
echo "Database is up and accepting connections!"

echo "=== 4. Waiting for Frappe (Gunicorn) to be Ready ==="
echo "Polling Frappe backend service..."
until docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe curl -s -o /null -w "%{http_code}" http://localhost:8000 | grep -E "^(200|301|302|404)" > /dev/null; do
    echo "Frappe backend (Gunicorn) is starting up, waiting 3 seconds..."
    sleep 3
done
echo "Frappe backend is responsive!"

echo "=== 4. Optional: Importing External Sites & Syncing Encryption Keys ==="
# TARGET_SITES_VOLUME_DIR="/var/lib/docker/volumes/${PROJECT_NAME}/_data"

# # Dynamically resolve the target sites volume mount point from Docker
# # (Assuming your volume in docker-compose.yml is named 'sites-data')
# TARGET_VOLUME_NAME=$(docker compose -f ${DOCKER_COMPOSE_FILE} config --volumes | grep -E "site" | head -n 1)
# if [ -z "$TARGET_VOLUME_NAME" ]; then
#     TARGET_VOLUME_NAME="sites-data" # Fallback default name
# fi

# TARGET_SITES_VOLUME_DIR=$(docker volume inspect "$(docker compose ls --filter name=$(basename "$PWD") --format '{{.Name}}')_${TARGET_VOLUME_NAME}" --format '{{ .Mountpoint }}' 2>/dev/null || docker volume inspect "${TARGET_VOLUME_NAME}" --format '{{ .Mountpoint }}' 2>/dev/null || echo "")

# if [ -z "$TARGET_SITES_VOLUME_DIR" ]; then
#     echo "Error: Could not determine target Docker volume mount point. Ensure containers have been started at least once."
#     exit 1
# fi

# Dynamically find the target sites volume name from Docker
TARGET_VOLUME_NAME=$(docker volume ls -q | grep -E "sites" | head -n 1)
if [ -z "$TARGET_VOLUME_NAME" ]; then
    TARGET_VOLUME_NAME="sites-data"
fi

# Get the host mountpoint for the volume
TARGET_SITES_VOLUME_DIR=$(docker volume inspect "$TARGET_VOLUME_NAME" --format '{{ .Mountpoint }}' 2>/dev/null || echo "")

if [ -z "$TARGET_SITES_VOLUME_DIR" ]; then
    echo "Error: Could not determine target Docker volume mount point. Ensure your containers and volumes have been started at least once."
    exit 1
fi

# Ensure the target directory exists before copying
mkdir -p "$TARGET_SITES_VOLUME_DIR"

if [ "$IMPORT_EXTERNAL_SITE" = "true" ]; then
    if [ -n "$EXTERNAL_SITES_DIR" ] && [ -d "$EXTERNAL_SITES_DIR" ]; then
        echo "Scanning external sites directory: $EXTERNAL_SITES_DIR"
        for SITE_DIR in "$EXTERNAL_SITES_DIR"/*; do
            if [ -d "$SITE_DIR" ]; then
                SITE_NAME=$(basename "$SITE_DIR")
                
                # Ignore non-site system directories
                if [[ "$SITE_NAME" != "assets" && "$SITE_NAME" != "private" && "$SITE_NAME" != "common_site_config.json" ]]; then
                    TARGET_SITE_PATH="$TARGET_SITES_VOLUME_DIR/$SITE_NAME"
                    
                    if [ ! -d "$TARGET_SITE_PATH" ]; then
                        echo "Restoring external site files for: $SITE_NAME"
                        cp -r "$SITE_DIR" "$TARGET_SITES_VOLUME_DIR/"
                        
                        # 1. Sync encryption key to prevent decryption errors
                        SOURCE_CONFIG="$EXTERNAL_SITES_DIR/common_site_config.json"
                        TARGET_CONFIG="$TARGET_SITES_VOLUME_DIR/common_site_config.json"
                        
                        if [ -f "$SOURCE_CONFIG" ] && [ -f "$TARGET_CONFIG" ]; then
                            echo "Synchronizing encryption key for $SITE_NAME..."
                            python3 -c "
import json
try:
    with open('$SOURCE_CONFIG', 'r') as f:
        src = json.load(f)
    with open('$TARGET_CONFIG', 'r') as f:
        tgt = json.load(f)
    if 'encryption_key' in src:
        tgt['encryption_key'] = src['encryption_key']
        with open('$TARGET_CONFIG', 'w') as f:
            json.dump(tgt, f, indent=4)
        print('Encryption key successfully synchronized.')
except Exception as e:
    print(f'Error syncing encryption key: {e}')
"
                        fi

                        # 2. Optional: Import External Database
                        if [ "$IMPORT_EXTERNAL_DB" = "true" ] && [ -n "$EXTERNAL_DB_CONTAINER" ]; then
                            SITE_CONFIG_FILE="$TARGET_SITE_PATH/site_config.json"
                            if [ -f "$SITE_CONFIG_FILE" ]; then
                                DB_NAME=$(python3 -c "import json; print(json.load(open('$SITE_CONFIG_FILE')).get('db_name', ''))")
                                
                                if [ -n "$DB_NAME" ]; then
                                    echo "Found database name '$DB_NAME' for site $SITE_NAME. Extracting from external container..."
                                    TEMP_SQL="/tmp/${DB_NAME}_backup.sql"
                                    
                                    # Dump database from existing external container
                                    docker exec -t "$EXTERNAL_DB_CONTAINER" mysqldump -u root -p"$EXTERNAL_DB_ROOT_PASSWORD" --databases "$DB_NAME" > "$TEMP_SQL" || echo "Warning: Database dump encountered warnings."
                                    
                                    if [ -f "$TEMP_SQL" ] && [ -s "$TEMP_SQL" ]; then
                                        echo "Importing database '$DB_NAME' into new deployment..."
                                        docker compose -f ${DOCKER_COMPOSE_FILE} exec -T db mysql -u root -p"${DB_ROOT_PASSWORD}" < "$TEMP_SQL"
                                        rm -f "$TEMP_SQL"
                                        echo "Database $DB_NAME imported successfully!"
                                    else
                                        echo "Error: Generated SQL dump for $DB_NAME was empty or failed."
                                    fi
                                else
                                    echo "Could not find 'db_name' in site_config.json for $SITE_NAME."
                                fi
                            fi
                        fi
                    else
                        echo "Site $SITE_NAME already exists in target volume. Skipping import."
                    fi
                fi
            fi
        done
    else
        echo "IMPORT_EXTERNAL_SITE is true, but EXTERNAL_SITES_DIR is invalid or missing: $EXTERNAL_SITES_DIR"
    fi
else
    echo "External site import is disabled."
fi

echo "=== 5. Managing Backups & Disk Space ==="
mkdir -p "$BACKUP_DIR"

# Cleanup backups older than 7 days
echo "Cleaning up backup archives older than 7 days..."
find "$BACKUP_DIR" -type f \( -name "*.sql" -o -name "*.tar.gz" \) -mtime +7 -exec rm -f {} \;

# Backup MariaDB Database and Frappe Sites data
echo "Backing up MariaDB database and Frappe site files..."
docker compose -f ${DOCKER_COMPOSE_FILE} exec -T db mysqldump -u root -p"${DB_ROOT_PASSWORD}" --all-databases > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
tar -czf "$BACKUP_DIR/sites_backup_$TIMESTAMP.tar.gz" -C /var/lib/docker/volumes/${PROJECT_NAME}_sites-data/_data . 2>/dev/null || echo "Sites archive created with warnings or skipped direct path."

echo "Backup completed successfully at $BACKUP_DIR/"

echo "=== 6. Running Dynamic Frappe Database Migrations with Maintenance Mode ==="
# Find all site directories inside the container, excluding assets and common config files
SITES=$(docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe python3 -c "
import os
sites_path = '/home/frappe/frappe-bench/sites'
ignored = {'assets', 'common_site_config.json', 'private'}
sites = [d for d in os.listdir(sites_path) if os.path.isdir(os.path.join(sites_path, d)) and d not in ignored]
print(' '.join(sites))
")

if [ -z "$SITES" ]; then
    echo "No active Frappe sites found to migrate."
else
    echo "Detected sites: $SITES"
    for SITE in $SITES; do
        echo "--------------------------------------------------"
        echo "Processing site: $SITE"

        echo "Enabling maintenance mode for $SITE..."
        docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe bench --site "$SITE" set-maintenance-mode on || true

        # Ensure maintenance mode is disabled even if migration fails midway
        trap "docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe bench --site '$SITE' set-maintenance-mode off || true" EXIT

        echo "Migrating $SITE..."
        docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe bench --site "$SITE" migrate
        docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe bench --site "$SITE" clear-cache

        echo "Disabling maintenance mode for $SITE..."
        docker compose -f ${DOCKER_COMPOSE_FILE} exec -T frappe bench --site "$SITE" set-maintenance-mode off
        
        # Reset trap for next iteration
        trap - EXIT
    done
fi

echo "=== 7. Pruning Unused Docker Images ==="
docker image prune -f

echo "=== Deployment & Dynamic Migration Completed Successfully! ==="