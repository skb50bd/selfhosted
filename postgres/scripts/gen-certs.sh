#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Certificate Generation Script for PostgreSQL
# Generates: Root CA, Server Certs, Client Certs (for app + replication)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
VALIDITY_DAYS=3650 # 10 years

# Create certs directory structure
mkdir -p "${CERTS_DIR}"/{ca,server,clients/{app,replication}}

echo "==> Generating Root CA..."
openssl genrsa -out "${CERTS_DIR}/ca/ca.key" 4096
openssl req -new -x509 -days ${VALIDITY_DAYS} -key "${CERTS_DIR}/ca/ca.key" \
    -out "${CERTS_DIR}/ca/ca.crt" \
    -subj "/CN=PostgreSQL-Root-CA/O=SelfHosted/C=BD"

# -----------------------------------------------------------------------------
# Server Certificate (used by both primary and replica)
# Uses SANs for multiple hostnames
# -----------------------------------------------------------------------------
echo "==> Generating Server Certificate..."

cat > "${CERTS_DIR}/server/server.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = postgres-server
O = SelfHosted
C = BD

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = postgres-primary
DNS.2 = postgres-replica
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out "${CERTS_DIR}/server/server.key" 4096
openssl req -new -key "${CERTS_DIR}/server/server.key" \
    -out "${CERTS_DIR}/server/server.csr" \
    -config "${CERTS_DIR}/server/server.cnf"
openssl x509 -req -in "${CERTS_DIR}/server/server.csr" \
    -CA "${CERTS_DIR}/ca/ca.crt" -CAkey "${CERTS_DIR}/ca/ca.key" \
    -CAcreateserial -out "${CERTS_DIR}/server/server.crt" \
    -days ${VALIDITY_DAYS} \
    -extensions v3_req -extfile "${CERTS_DIR}/server/server.cnf"

# -----------------------------------------------------------------------------
# Client Certificate for Application User (CN=appuser)
# -----------------------------------------------------------------------------
echo "==> Generating Client Certificate for appuser..."

cat > "${CERTS_DIR}/clients/app/client.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = appuser
O = SelfHosted
C = BD
EOF

openssl genrsa -out "${CERTS_DIR}/clients/app/client.key" 4096
openssl req -new -key "${CERTS_DIR}/clients/app/client.key" \
    -out "${CERTS_DIR}/clients/app/client.csr" \
    -config "${CERTS_DIR}/clients/app/client.cnf"
openssl x509 -req -in "${CERTS_DIR}/clients/app/client.csr" \
    -CA "${CERTS_DIR}/ca/ca.crt" -CAkey "${CERTS_DIR}/ca/ca.key" \
    -CAcreateserial -out "${CERTS_DIR}/clients/app/client.crt" \
    -days ${VALIDITY_DAYS}

# -----------------------------------------------------------------------------
# Client Certificate for Replication User (CN=replicator)
# -----------------------------------------------------------------------------
echo "==> Generating Client Certificate for replicator..."

cat > "${CERTS_DIR}/clients/replication/client.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = replicator
O = SelfHosted
C = BD
EOF

openssl genrsa -out "${CERTS_DIR}/clients/replication/client.key" 4096
openssl req -new -key "${CERTS_DIR}/clients/replication/client.key" \
    -out "${CERTS_DIR}/clients/replication/client.csr" \
    -config "${CERTS_DIR}/clients/replication/client.cnf"
openssl x509 -req -in "${CERTS_DIR}/clients/replication/client.csr" \
    -CA "${CERTS_DIR}/ca/ca.crt" -CAkey "${CERTS_DIR}/ca/ca.key" \
    -CAcreateserial -out "${CERTS_DIR}/clients/replication/client.crt" \
    -days ${VALIDITY_DAYS}

# -----------------------------------------------------------------------------
# Set permissions (PostgreSQL requires strict permissions on keys)
# -----------------------------------------------------------------------------
echo "==> Setting file permissions..."
chmod 600 "${CERTS_DIR}/ca/ca.key"
chmod 600 "${CERTS_DIR}/server/server.key"
chmod 600 "${CERTS_DIR}/clients/app/client.key"
chmod 600 "${CERTS_DIR}/clients/replication/client.key"

# Certs can be world-readable
chmod 644 "${CERTS_DIR}/ca/ca.crt"
chmod 644 "${CERTS_DIR}/server/server.crt"
chmod 644 "${CERTS_DIR}/clients/app/client.crt"
chmod 644 "${CERTS_DIR}/clients/replication/client.crt"

echo "==> Certificates generated successfully in: ${CERTS_DIR}"
echo ""
echo "Files created:"
find "${CERTS_DIR}" -type f -name "*.crt" -o -name "*.key" | sort
