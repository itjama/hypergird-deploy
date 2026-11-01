#!/usr/bin/env bash
# Nasadenie: ./deploy.sh 0.1.0   → nastaví APP_VERSION v .env a nasadí
#            ./deploy.sh         → nasadí APP_VERSION, ktorá už je v .env
# Poradie: stiahnuť image → záloha DB (pred migráciou) → spustiť → čakať na healthcheck.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "✗ Chýba .env (cp .env.example .env a vyplniť)"; exit 1; }

if [ $# -ge 1 ]; then
  sed -i "s/^APP_VERSION=.*/APP_VERSION=${1#v}/" .env
fi
APP_VERSION="$(grep -E '^APP_VERSION=' .env | cut -d= -f2)"
[ -n "$APP_VERSION" ] || { echo "✗ APP_VERSION v .env je prázdna"; exit 1; }
echo "→ Nasadzujem verziu $APP_VERSION"

docker compose pull

# Pri prvom nasadení DB ešte nebeží → nie je čo zálohovať
if [ -n "$(docker compose ps -q db --status running)" ]; then
  ./backup.sh
fi

docker compose up -d --remove-orphans --wait --wait-timeout 300

# nginx vo webe si IP servera zisťuje iba pri štarte
docker compose restart web

docker image prune -f >/dev/null
echo "✓ Beží verzia $APP_VERSION"
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
