# PostgreSQL with pgvector and Caddy L4 TLS

A distributed PostgreSQL setup with:
- **pgvector** for vector similarity search
- **Caddy L4** for automatic Let's Encrypt TLS on port 443
- **Async Streaming Replication** across WAN
- **Password Authentication** only (no client certs)
- **Single compose file** for all instances (role via ENV)

## Quick Start

```bash
# Primary (Machine A)
POSTGRES_DOMAIN=pg.example.com \
REPLICATION_PASSWORD=secret123 \
PG_ROLE=primary \
docker compose up -d

# Set replicator password after first start
REPLICATION_PASSWORD=secret123 ./scripts/set-replication-password.sh
```

```bash
# Replica (Machine B)
POSTGRES_DOMAIN=pg-replica.example.com \
REPLICATION_PASSWORD=secret123 \
PRIMARY_HOST=pg.example.com \
PRIMARY_PORT=443 \
PG_ROLE=replica \
docker compose up -d
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PG_ROLE` | `primary` or `replica` | `primary` |
| `POSTGRES_DOMAIN` | Domain for TLS cert | `pg.localhost` |
| `PRIMARY_HOST` | Primary hostname (for replicas) | - |
| `PRIMARY_PORT` | Primary port (for replicas) | `5432` |
| `POSTGRES_PASSWORD` | Superuser password | `postgres` |
| `REPLICATION_PASSWORD` | Replicator password | - |

## Connecting

```bash
# Connect via TLS on port 5432
psql "host=pg.example.com port=5432 sslmode=require user=postgres password=yourpassword dbname=postgres"
```

## Check Replication Status

```bash
./scripts/replication-status.sh pg.example.com 443
```

## Failover (Promote Replica)

```bash
# On replica to promote:
PG_ROLE=primary docker compose up -d

# Update other replicas:
PRIMARY_HOST=pg-replica.example.com docker compose up -d
```

## Files

```
postgres/
├── compose.yaml              # Caddy + PostgreSQL services
├── caddy/
│   ├── Dockerfile            # Caddy with L4 plugin
│   └── Caddyfile             # L4 TLS config on port 443
├── config/
│   ├── postgresql.conf       # PG settings (SSL off - Caddy handles TLS)
│   └── pg_hba.conf           # Password auth rules
├── scripts/
│   ├── entrypoint.sh         # Primary/replica entrypoint
│   ├── init-primary.sql      # DB initialization
│   ├── set-replication-password.sh
│   └── replication-status.sh
```
