# PostgreSQL with pgvector, TLS, and Async Replication

A distributed PostgreSQL setup with:
- **pgvector** for vector similarity search
- **TLS/SSL** with self-signed certificates
- **Async Streaming Replication** across WAN
- **Certificate + Password Authentication**
- **Single compose file** for all instances (role via ENV)

## Quick Start

```bash
# 1. Generate certificates (do this once, copy to all machines)
chmod +x scripts/*.sh
./scripts/gen-certs.sh

# 2. Copy the entire postgres/ folder to each machine
```

### Start Primary (Machine A)
```bash
PG_ROLE=primary docker compose up -d
```

### Start Replica (Machine B, C, ...)
```bash
PG_ROLE=replica PRIMARY_HOST=machineA.example.com docker compose up -d
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PG_ROLE` | `primary` or `replica` | `primary` |
| `PRIMARY_HOST` | Hostname/IP of primary | (required for replica) |
| `PRIMARY_PORT` | Port of primary | `5432` |
| `POSTGRES_PASSWORD` | Superuser password | `postgres` |
| `POSTGRES_PORT` | Host port to bind | `5432` |

## Check Replication Status

```bash
# On any node
./scripts/replication-status.sh localhost 5432
```

**Primary output:** Shows connected replicas and lag  
**Replica output:** Shows replication lag and connection to primary

## Failover (Promote Replica to Primary)

```bash
# 1. On old primary (if accessible)
docker compose down

# 2. On replica to promote
PG_ROLE=primary docker compose up -d
# The entrypoint will remove standby.signal and start as primary

# 3. Update other replicas to point to new primary
PRIMARY_HOST=newprimary.example.com docker compose up -d
```

## Users

| User | Auth | Purpose |
|------|------|---------|
| `postgres` | trust (local) | Superuser |
| `appuser` | Certificate | App connections |
| `pwduser` | Password (`pwduser_secret`) | Password auth |
| `replicator` | Certificate | Replication |

## Connecting

### Certificate Auth
```bash
PGSSLCERT=certs/clients/app/client.crt \
PGSSLKEY=certs/clients/app/client.key \
PGSSLROOTCERT=certs/ca/ca.crt \
PGSSLMODE=verify-ca \
psql -h <HOST> -p 5432 -U appuser -d postgres
```

### Password Auth
```bash
PGSSLROOTCERT=certs/ca/ca.crt \
PGSSLMODE=verify-ca \
PGPASSWORD=pwduser_secret \
psql -h <HOST> -p 5432 -U pwduser -d postgres
```

## Creating New Users

### New Password User

1. **Create the user in PostgreSQL** (on primary):
```bash
docker exec -it postgres psql -U postgres -c "
  CREATE ROLE myuser WITH LOGIN PASSWORD 'mypassword';
  GRANT CONNECT ON DATABASE postgres TO myuser;
  GRANT USAGE ON SCHEMA public TO myuser;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myuser;
"
```

2. **Connect** (password auth is already enabled for all users in `pg_hba.conf`):
```bash
PGSSLROOTCERT=certs/ca/ca.crt PGSSLMODE=verify-ca PGPASSWORD=mypassword \
psql -h <HOST> -p 5432 -U myuser -d postgres
```

### New Certificate User

1. **Generate client certificate** (CN must match username):
```bash
# Create directory
mkdir -p certs/clients/myuser

# Generate key and CSR
openssl genrsa -out certs/clients/myuser/client.key 4096
openssl req -new -key certs/clients/myuser/client.key \
  -out certs/clients/myuser/client.csr \
  -subj "/CN=myuser/O=SelfHosted/C=BD"

# Sign with CA
openssl x509 -req -in certs/clients/myuser/client.csr \
  -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
  -out certs/clients/myuser/client.crt -days 3650

# Set permissions
chmod 600 certs/clients/myuser/client.key
chmod 644 certs/clients/myuser/client.crt
```

2. **Create the user in PostgreSQL** (on primary):
```bash
docker exec -it postgres psql -U postgres -c "
  CREATE ROLE myuser WITH LOGIN;
  GRANT CONNECT ON DATABASE postgres TO myuser;
  GRANT USAGE ON SCHEMA public TO myuser;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myuser;
"
```

3. **Add cert auth rule to `pg_hba.conf`** (before the password fallback rule):
```conf
hostssl all             myuser          0.0.0.0/0               cert
hostssl all             myuser          ::/0                    cert
```

4. **Reload config** (or restart):
```bash
docker exec -it postgres psql -U postgres -c "SELECT pg_reload_conf();"
```

5. **Connect**:
```bash
PGSSLCERT=certs/clients/myuser/client.crt \
PGSSLKEY=certs/clients/myuser/client.key \
PGSSLROOTCERT=certs/ca/ca.crt \
PGSSLMODE=verify-ca \
psql -h <HOST> -p 5432 -U myuser -d postgres
```

## Files

```
postgres/
├── compose.yaml              # Single-service compose (role via ENV)
├── config/
│   ├── postgresql.conf       # TLS + async replication settings
│   └── pg_hba.conf           # Authentication rules
├── scripts/
│   ├── gen-certs.sh          # Certificate generation
│   ├── entrypoint.sh         # Unified primary/replica entrypoint
│   ├── init-primary.sql      # Primary initialization
│   ├── replication-status.sh # Monitoring script
│   └── verify.sh             # Local test script
└── certs/                    # Generated certificates (gitignored)
```
