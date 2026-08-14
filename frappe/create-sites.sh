#!/bin/bash
set -e

# Target bench path inside the container
BENCH_DIR="/home/frappe/frappe-bench"

# Ensure we are operating inside the bench directory
cd "$BENCH_DIR"
 
# Set fallback default site
echo "$NYERI_SITE_NAME" > sites/current_site.txt

# 1. Wait for critical backing infrastructure
echo "Waiting for MariaDB..."
wait-for-it -t 120 "$DB_HOST:$DB_PORT" -- echo "MariaDB is up and running!"
echo "Waiting for Redis Cache..."
wait-for-it -t 120 redis-cache:6379 -- echo "Redis Cache is up and running!"
echo "Waiting for Redis Queue..."
wait-for-it -t 120 redis-queue:6379 -- echo "Redis Queue is up and running!"

# Set Common/Global DB Host config
bench set-config -g db_host db
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379
bench set-config -g redis_socketio redis://redis-queue:6379

# Build missing asset links
bench build || true

# Helper function to create site if it doesn't exist
create_site_if_missing() {
  SITE_NAME=$1
  if [ ! -d "sites/$SITE_NAME" ]; then
    echo "Creating site: $SITE_NAME"
    bench new-site $SITE_NAME \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --no-mariadb-socket
    
    # Enable DNS-based multitenancy or port mapping
    # bench --site $SITE_NAME set-config allow_cors "*"
  else
    echo "Site $SITE_NAME already exists. Skipping creation."
  fi

  # install apps
  for APP in $APPS; do
    install_app "$SITE_NAME" "$APP"
  done
}

# Helper function to create site if it doesn't exist
install_app() {
  SITE_NAME=$1
  APP_NAME=$2
  if [ ! -d "sites/$SITE_NAME" ]; then
    echo "Site: $SITE_NAME does not exist. Exiting..."
    exit 1 
  else
    echo "📦 Installing $APP_NAME on $SITE_NAME..."
    bench --site "$SITE_NAME" install-app "$APP_NAME" 
  fi
} 

create_site_if_missing "$NYERI_SITE_NAME"
create_site_if_missing "$MURANGA_SITE_NAME"

# Enable Multitenancy
bench config dns_multitenant off

# Frappe sets cookie attributes (SameSite and HttpOnly) that can prevent local cross-origin requests from returning the session cookie to http://localhost:3000.
# Set same_site to Lax or None
bench config set-common-config -c same_site Lax

echo "Starting Frappe Backend via Gunicorn..."
exec "$BENCH_DIR/env/bin/gunicorn" \
  --chdir $BENCH_DIR/sites \
  --bind 0.0.0.0:8000 \
  --workers 4 \
  --worker-class gthread \
  --threads 2 \
  --timeout 120 \
  --preload \
  frappe.app:application