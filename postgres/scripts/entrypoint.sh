#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Unified Entrypoint for PostgreSQL Primary/Replica
# Role is determined by PG_ROLE environment variable
# =============================================================================

PG_ROLE="${PG_ROLE:-primary}"
PGDATA="${PGDATA:-/var/lib/postgresql/data}"

# Primary connection info (for replicas)
PRIMARY_HOST="${PRIMARY_HOST:-}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICATION_USER="${REPLICATION_USER:-replicator}"

# Certificate paths
CERT_DIR="/var/lib/postgresql/certs"
CLIENT_CERT="${CERT_DIR}/clients/replication/client.crt"
CLIENT_KEY="${CERT_DIR}/clients/replication/client.key"
CA_CERT="${CERT_DIR}/ca/ca.crt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# =============================================================================
# REPLICA MODE
# =============================================================================
setup_replica() {
    log "==> Starting as REPLICA"
    log "    Primary: ${PRIMARY_HOST}:${PRIMARY_PORT}"
    log "    PGDATA: ${PGDATA}"

    if [ -z "${PRIMARY_HOST}" ]; then
        log "ERROR: PRIMARY_HOST is required for replica mode"
        exit 1
    fi

    # Check if PGDATA is empty or uninitialized
    if [ -z "$(ls -A "${PGDATA}" 2>/dev/null)" ] || [ ! -f "${PGDATA}/PG_VERSION" ]; then
        log "==> PGDATA is empty. Waiting for primary to be ready..."

        # Wait for primary to accept connections
        ATTEMPTS=0
        MAX_ATTEMPTS=120  # 4 minutes for WAN connections
        until PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_isready -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U postgres; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]; then
                log "ERROR: Primary not ready after ${MAX_ATTEMPTS} attempts. Exiting."
                exit 1
            fi
            log "    Waiting for primary... (${ATTEMPTS}/${MAX_ATTEMPTS})"
            sleep 2
        done

        log "==> Primary is ready. Starting pg_basebackup..."

        # Create PGDATA directory with correct permissions
        mkdir -p "${PGDATA}"
        chmod 700 "${PGDATA}"
        chown postgres:postgres "${PGDATA}"

        # Run pg_basebackup with certificate authentication
        pg_basebackup \
            -h "${PRIMARY_HOST}" \
            -p "${PRIMARY_PORT}" \
            -U "${REPLICATION_USER}" \
            -D "${PGDATA}" \
            -Fp \
            -Xs \
            -P \
            -R \
            --checkpoint=fast \
            --no-password \
            -d "sslmode=verify-ca sslcert=${CLIENT_CERT} sslkey=${CLIENT_KEY} sslrootcert=${CA_CERT}"

        log "==> pg_basebackup completed successfully."

        # Ensure standby.signal exists
        touch "${PGDATA}/standby.signal"

        # Configure primary_conninfo with certificate auth
        cat >> "${PGDATA}/postgresql.auto.conf" <<EOF

# Replication connection info (certificate auth, async)
primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=${REPLICATION_USER} sslmode=verify-ca sslcert=${CLIENT_CERT} sslkey=${CLIENT_KEY} sslrootcert=${CA_CERT} application_name=${HOSTNAME}'
EOF

        chown -R postgres:postgres "${PGDATA}"
        log "==> Replica bootstrap complete."
    else
        log "==> PGDATA already initialized."
        
        # Ensure standby.signal exists for replica
        if [ ! -f "${PGDATA}/standby.signal" ]; then
            touch "${PGDATA}/standby.signal"
            chown postgres:postgres "${PGDATA}/standby.signal"
        fi
    fi

    log "==> Starting PostgreSQL in replica mode..."
    exec docker-entrypoint.sh postgres \
        -c config_file=/etc/postgresql/postgresql.conf \
        -c hba_file=/etc/postgresql/pg_hba.conf
}

# =============================================================================
# PRIMARY MODE
# =============================================================================
setup_primary() {
    log "==> Starting as PRIMARY"
    log "    PGDATA: ${PGDATA}"

    # Remove standby.signal if it exists (in case of promotion)
    if [ -f "${PGDATA}/standby.signal" ]; then
        log "    Removing standby.signal (was previously a replica)"
        rm -f "${PGDATA}/standby.signal"
    fi

    log "==> Starting PostgreSQL in primary mode..."
    exec docker-entrypoint.sh postgres \
        -c config_file=/etc/postgresql/postgresql.conf \
        -c hba_file=/etc/postgresql/pg_hba.conf
}

# =============================================================================
# MAIN
# =============================================================================
case "${PG_ROLE}" in
    primary|master)
        setup_primary
        ;;
    replica|standby|slave)
        setup_replica
        ;;
    *)
        log "ERROR: Unknown PG_ROLE: ${PG_ROLE}"
        log "       Valid values: primary, replica"
        exit 1
        ;;
esac
