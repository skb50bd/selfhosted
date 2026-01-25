#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Set Replication Password Script
# Run this after starting primary to set the replicator password
# =============================================================================

REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-}"

if [ -z "${REPLICATION_PASSWORD}" ]; then
    echo "ERROR: REPLICATION_PASSWORD environment variable is required"
    exit 1
fi

echo "Setting replicator password..."
docker exec -it postgres psql -U postgres -c "ALTER ROLE replicator WITH PASSWORD '${REPLICATION_PASSWORD}';"
echo "Done!"
