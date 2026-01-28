#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Replication Status Script
# Shows replication info for both primary and replica nodes
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

HOST="${1:-localhost}"
PORT="${2:-5432}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

header() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# Connect as postgres superuser
psql_cmd() {
    PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
    PGSSLMODE=verify-ca \
    PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
    psql -h "${HOST}" -p "${PORT}" -U postgres -d postgres -t -A -F $'\t' "$@"
}

psql_pretty() {
    PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
    PGSSLMODE=verify-ca \
    PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
    psql -h "${HOST}" -p "${PORT}" -U postgres -d postgres "$@"
}

# Check if this is primary or replica
IS_RECOVERY=$(psql_cmd -c "SELECT pg_is_in_recovery();" 2>/dev/null || echo "error")

echo ""
echo "=============================================="
echo " PostgreSQL Replication Status"
echo " Host: ${HOST}:${PORT}"
echo "=============================================="

if [ "${IS_RECOVERY}" = "t" ]; then
    # This is a REPLICA
    header "Node Role: REPLICA (Standby)"

    header "Replication Lag"
    psql_pretty -c "
SELECT
    CASE
        WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 'Caught up'
        ELSE 'Lagging'
    END AS status,
    pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) AS replay_lag,
    COALESCE(
        EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int || ' seconds',
        'N/A'
    ) AS time_lag,
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn;
"

    header "Connection to Primary"
    psql_pretty -c "
SELECT
    sender_host,
    sender_port,
    status,
    conninfo
FROM pg_stat_wal_receiver;
"

elif [ "${IS_RECOVERY}" = "f" ]; then
    # This is a PRIMARY
    header "Node Role: PRIMARY"

    header "Connected Replicas"
    psql_pretty -c "
SELECT
    application_name AS replica_name,
    client_addr AS replica_ip,
    state,
    sync_state,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_lag,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication
ORDER BY application_name;
"

    header "Replication Slots"
    psql_pretty -c "
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;
"

else
    echo "ERROR: Could not connect to PostgreSQL at ${HOST}:${PORT}"
    exit 1
fi

echo ""
