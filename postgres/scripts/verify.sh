#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Verification Script for PostgreSQL Setup
# Tests: TLS, Certificate Auth, Password Auth, Replication, pgvector
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

PRIMARY_HOST="${PRIMARY_HOST:-localhost}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICA_HOST="${REPLICA_HOST:-localhost}"
REPLICA_PORT="${REPLICA_PORT:-5433}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; exit 1; }
info() { echo -e "${YELLOW}➤ INFO${NC}: $1"; }

# -----------------------------------------------------------------------------
# Test 1: TLS Connection with Client Certificate (appuser)
# -----------------------------------------------------------------------------
test_cert_auth() {
    info "Testing certificate authentication (appuser)..."
    
    RESULT=$(PGSSLCERT="${CERTS_DIR}/clients/app/client.crt" \
        PGSSLKEY="${CERTS_DIR}/clients/app/client.key" \
        PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U appuser -d postgres \
        -c "SELECT 'cert_auth_works' AS result;" -t -A 2>/dev/null) || fail "Certificate auth connection failed"
    
    if [[ "${RESULT}" == *"cert_auth_works"* ]]; then
        pass "Certificate authentication (appuser)"
    else
        fail "Certificate authentication query failed"
    fi
}

# -----------------------------------------------------------------------------
# Test 2: Password Authentication (pwduser)
# -----------------------------------------------------------------------------
test_password_auth() {
    info "Testing password authentication (pwduser)..."
    
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="pwduser_secret" \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U pwduser -d postgres \
        -c "SELECT 'password_auth_works' AS result;" -t -A 2>/dev/null) || fail "Password auth connection failed"
    
    if [[ "${RESULT}" == *"password_auth_works"* ]]; then
        pass "Password authentication (pwduser)"
    else
        fail "Password authentication query failed"
    fi
}

# -----------------------------------------------------------------------------
# Test 3: TLS is enforced (connection info shows SSL)
# -----------------------------------------------------------------------------
test_tls_enforced() {
    info "Testing TLS enforcement..."
    
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="pwduser_secret" \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U pwduser -d postgres \
        -c "SHOW ssl;" -t -A 2>/dev/null) || fail "SSL check query failed"
    
    if [[ "${RESULT}" == "on" ]]; then
        pass "TLS is enabled on server"
    else
        fail "TLS is not enabled"
    fi
}

# -----------------------------------------------------------------------------
# Test 4: pgvector extension is available
# -----------------------------------------------------------------------------
test_pgvector() {
    info "Testing pgvector extension..."
    
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="pwduser_secret" \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U pwduser -d postgres \
        -c "SELECT extname FROM pg_extension WHERE extname = 'vector';" -t -A 2>/dev/null)
    
    if [[ "${RESULT}" == "vector" ]]; then
        pass "pgvector extension is installed"
    else
        fail "pgvector extension not found"
    fi
}

# -----------------------------------------------------------------------------
# Test 5: Streaming Replication is active
# -----------------------------------------------------------------------------
test_replication() {
    info "Testing streaming replication..."
    
    # Check replication status on primary
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U postgres -d postgres \
        -c "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';" -t -A 2>/dev/null)
    
    if [[ "${RESULT}" -ge 1 ]]; then
        pass "Streaming replication is active (${RESULT} replica(s))"
    else
        fail "No active streaming replicas found"
    fi
}

# -----------------------------------------------------------------------------
# Test 6: Data replication (write on primary, read on replica)
# -----------------------------------------------------------------------------
test_data_replication() {
    info "Testing data replication (write primary -> read replica)..."
    
    # Insert a unique row on primary
    UNIQUE_ID=$(date +%s%N)
    PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
        psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U postgres -d postgres \
        -c "INSERT INTO test_vectors (content, embedding) VALUES ('test_${UNIQUE_ID}', '[1,1,1]');" >/dev/null 2>&1 || fail "Insert on primary failed"
    
    # Wait a moment for replication
    sleep 2
    
    # Read from replica
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
        psql -h "${REPLICA_HOST}" -p "${REPLICA_PORT}" -U postgres -d postgres \
        -c "SELECT content FROM test_vectors WHERE content = 'test_${UNIQUE_ID}';" -t -A 2>/dev/null)
    
    if [[ "${RESULT}" == "test_${UNIQUE_ID}" ]]; then
        pass "Data replication verified"
    else
        fail "Data not replicated to replica"
    fi
}

# -----------------------------------------------------------------------------
# Test 7: Replica is read-only
# -----------------------------------------------------------------------------
test_replica_readonly() {
    info "Testing replica is read-only..."
    
    RESULT=$(PGSSLROOTCERT="${CERTS_DIR}/ca/ca.crt" \
        PGSSLMODE=verify-ca \
        PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
        psql -h "${REPLICA_HOST}" -p "${REPLICA_PORT}" -U postgres -d postgres \
        -c "INSERT INTO test_vectors (content, embedding) VALUES ('should_fail', '[0,0,0]');" 2>&1) || true
    
    if [[ "${RESULT}" == *"read-only"* ]] || [[ "${RESULT}" == *"cannot execute"* ]]; then
        pass "Replica is read-only"
    else
        fail "Replica should be read-only but accepted write"
    fi
}

# -----------------------------------------------------------------------------
# Run all tests
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " PostgreSQL Setup Verification"
echo "=============================================="
echo ""

test_tls_enforced
test_cert_auth
test_password_auth
test_pgvector
test_replication
test_data_replication
test_replica_readonly

echo ""
echo "=============================================="
echo -e " ${GREEN}All tests passed!${NC}"
echo "=============================================="
echo ""
