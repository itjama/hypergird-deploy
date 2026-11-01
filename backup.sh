#!/usr/bin/env bash
# Záloha DB: backups/db-<čas>.dump (pg_dump -Fc), staršie ako KEEP_DAYS sa mažú.
set -euo pipefail
cd "$(dirname "$0")"

set -a; . ./.env; set +a
TS="$(date +%Y%m%d-%H%M%S)"

umask 077
mkdir -p backups

echo "→ DB záloha backups/db-$TS.dump"
docker compose exec -T db pg_dump -U hypergrid -d hypergrid -Fc > "backups/db-$TS.dump"
find backups -name 'db-*.dump' -mtime +"${KEEP_DAYS:-14}" -delete

echo "✓ Záloha hotová"
