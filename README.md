# Automated Deployment Guide

Welcome to the **Engage-App Automated Deployment Guide**. This document provides simple, step-by-step instructions for publishing updates and running system deployments.

You are able to deploy the Frappe backend applications as well as optionally the Engage frontend or the Project Tracking and Monitory System frontend. So choose accordingly by referencing the correct docker compose file i.e **docker-compose.engage.yml** or **docker-compose.pmts.yml**.

```bash
docker compose -f docker-compose.engage.yml -p <OPTIONAL_PROJECT_NAME> up -d
```

or

```bash
docker compose -f docker-compose.pmts.yml -p <OPTIONAL_PROJECT_NAME> up -d
```

Whether you are performing routine software updates, configuring reverse proxies, or migrating data from an existing environment, these automated tools handle complex backend operations safely in the background.

---

## Introduction & Overview

Our deployment architecture uses Docker containers to run Frappe, EngageApp Web, MariaDB databases, and Nginx web servers. 

To simplify maintenance, the system is driven by two automated scripts:
1. **`_publish.sh`**: Run locally to build, tag, and push new software versions to Docker Hub.
2. **`_deploy.sh`**: Executed on the live server to pull updates, perform automated safety backups, synchronize site files and encryption keys, run site migrations, and clean up disk space.

docker-compose files contain an option to either build from local context or pull from pre-built images. See the example below:

```bash

homabay-engage-app:
    pull_policy: never
    build:
      context: ~/systems/engage-frontend/
      dockerfile: deploy/Dockerfile
      args:
        EXPO_PUBLIC_FRAPPE_URL_WEB: "http://localhost:${HOMABAY_BACKEND_PORT}"
    image: ${DOCKERHUB_USER}/homabay-engage-app:${VERSION}

```

### Directory Organization

```
.
├── .env                    # System environment configuration (credentials, flags)
├── docker-compose.yml      # Service definitions, networks, and volume mounts
├── deploy.sh               # Main automated deployment and migration script
├── publish.sh              # Builder script to push new images to Docker Hub
├── backups/                # Local storage directory for automated SQL & site archives
└── proxy/                  # Reverse proxy and SSL/TLS configuration directory
    └── Nginx.conf          # Edge proxy routing configuration
```

---


## Core Concepts Explained Simply

* **Docker Containers**: Self-contained packages holding the application code, libraries, and system dependencies needed to run Frappe/ERPNext reliably across environments.
* **Database Migrations (`bench migrate`)**: Automatic updates applied to database tables to reflect new code changes without altering user data.
* **Maintenance Mode**: A temporary safety screen shown to site visitors during migrations to prevent data corruption while database structures are updated.
* **Site Restoration & Encryption Keys**: Automatically syncs site configuration and security keys when importing existing sites across environments.

---

## Container Roles & Responsibilities

Each service in the Docker Compose stack fulfills a specific function:

| Container / Service | Role & Responsibility |
| :--- | :--- |
| `frappe` | **App Backend (Gunicorn)**: Executes Python code, handles business logic, and manages Frappe sites. |
| `db` | **Database (MariaDB 10.6)**: Stores site data, user records, and application schemas. Configured with a `512M` `max_allowed_packet` limit. |
| `redis-cache` | **In-Memory Cache**: Speeds up site performance by caching sessions, permissions, and database queries. |
| `redis-queue` | **Task Queue Broker**: Manages background worker jobs (e.g., email dispatch, scheduled reports). |
| `edge-proxy` | **Web Gateway (Nginx)**: Routes external HTTPS/HTTP traffic to the Frappe app and serves static assets. |
| `*-engage-app*` | **Web version of the mobile app**: Renders forms and tools that are accessible to the public. |
---

## Configuring `edge-proxy`

The `edge-proxy` container acts as the entry point for all web traffic targeting your site.

### Key Steps to Configure Edge Proxy:

1. **Port Mapping**: By default, `edge-proxy` maps external port `8081` (or `80`/`443`) to the internal container network.
2. **Domain & Site Names**: Ensure your domain name (e.g., `erp.yourdomain.com`) matches the Frappe site directory created inside the volume.
3. **Updating Proxy Config**: If routing rules or SSL certificates change, modify `proxy/Nginx.conf` and reload the service:
   ```bash
   docker compose restart edge-proxy
   ```

---

## Automated Backup Management

Backups are executed automatically as **Step 5** of every `deploy.sh` run:

* **MariaDB Database Dump**: A full `mysqldump` of all databases is saved as `db_backup_TIMESTAMP.sql`.
* **Site File Archive**: User uploads and site configurations are compressed into `sites_backup_TIMESTAMP.tar.gz`.
* **7-Day Retention Cleanup**: To save disk space, the script automatically searches the `./backups/` directory and prunes archives older than 7 days:
  ```bash
  find "$BACKUP_DIR" -type f \( -name "*.sql" -o -name "*.tar.gz" \) -mtime +7 -exec rm -f {} \;
  ```

---

## How to Apply New Updates

When developer updates or new image releases are ready, follow these steps to apply updates safely:

### Step 1: Push New Image (Developer / CI Step)
From your local machine, run `publish.engage.sh` to build and push updated images to Docker Hub:
```bash
./publish.engage.sh
```

### Step 2: Apply Updates on Server
Log into your server terminal and execute `deploy.engage.sh`:
```bash
sudo ./deploy.engage.sh
```

### What Happens During Update Execution:
1. **Container Recreation**: Old containers are stopped cleanly using `docker compose down --remove-orphans`, releasing port bindings.
2. **Image Pulling**: Downloads the latest container images from Docker Hub.
3. **Health Verification**: Polls MariaDB and Frappe backend containers until healthy.
4. **Automated Safety Backup**: Creates a fresh snapshot of all databases and site files before changes are made.
5. **Site Migrations**: Toggles **Maintenance Mode** for each active site, runs `bench migrate` and `clear-cache`, then turns off Maintenance Mode.
6. **Disk Optimization**: Automatically prunes stale Docker image layers (`docker image prune -f`).

---

## Advanced Overrides (Optional External Data Import)

You can pass inline environment variables to import external site files and databases during deployment without editing `.env`:

```bash
sudo IMPORT_EXTERNAL_SITE="true" IMPORT_EXTERNAL_DB="true" ./deploy.engage.sh
```

This will automatically extract external site files, sync encryption keys from `common_site_config.json`, and import the site's database into your deployment.


## Configuration Setup (`.env`)

Before running a deployment, configuration values are managed in a `.env` file located in the root directory. 

Common parameters include:

| Variable | Description | Default / Example |
| :--- | :--- | :--- |
| `DB_ROOT_PASSWORD` | Password for database administration. | `your_db_password` |
| `DOCKER_HUB_USER` | Container repository account name. | `your-dockerhub-username` |
| `IMPORT_EXTERNAL_SITE` | Toggle (`true`/`false`) to restore site files from another system. | `false` |
| `IMPORT_EXTERNAL_DB` | Toggle (`true`/`false`) to import database dumps during migration. | `false` |
| `EXTERNAL_SITES_DIR` | Host path to the external site volume. | `/var/lib/docker/volumes/...` |
| `EXTERNAL_DB_CONTAINER` | Source database container name for imports. | `other-project-db-1` |

---

## How to Run a Standard Deployment

To perform a regular system update on the production server, open your server terminal and execute:

```bash
sudo ./deploy.engage.sh
```

### What Happens Automatically:
1. **Container Refresh**: Stops existing services cleanly and pulls fresh Docker images.
2. **Health Checks**: Polls MariaDB and Gunicorn backend services until they are fully responsive.
3. **Automated Backups**: Backs up all site databases and user upload files into `./backups/` and removes archives older than 7 days.
4. **Site Migrations**: Places active sites into maintenance mode, applies schema changes, clears system caches, and restores site access.
5. **Disk Optimization**: Cleans up unused Docker image layers to conserve storage space.

---

## Running Overrides (Advanced / Non-Technical Scenarios)

You can temporarily override configuration parameters without modifying the `.env` file directly by prefixing variables when invoking `deploy.engage.sh`.

### Scenario A: Importing an Existing External Site and Database
If you need to restore files and databases from a secondary setup during deployment:

```bash
sudo IMPORT_EXTERNAL_SITE="true" IMPORT_EXTERNAL_DB="true" ./deploy.engage.sh
```

### Scenario B: Custom Database Password Override
If you need to temporarily specify an alternative root password for database maintenance:

```bash
sudo DB_ROOT_PASSWORD="custom_root_password" ./deploy.engage.sh
```

---

## 6. Troubleshooting & Health Checks

* **Port Conflicts (`8081` in use)**: The deployment script automatically uses `docker compose down --remove-orphans` to release bound ports. If conflicts persist, restart Docker using `sudo systemctl restart docker`.
* **Database Connection Timeouts**: Verified by automatic health check polling during startup.
* **Restoring Maintenance Mode**: If a migration is interrupted, maintenance mode is automatically turned off via internal script traps upon completion.