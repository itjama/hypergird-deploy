# hypergird-deploy

Produkčné nasadenie aplikácie [hypergrid](https://github.com/itjama/hypergrid) na `https://hypergrid.app.iteo.sk`.
Žiadny kód aplikácie — iba konfigurácia servera. Image sa sťahujú zo súkromného GHCR.
HTTPS rieši spoločný Traefik (repo `traefik-deploy`), musí bežať a musí existovať sieť `proxy`.

```
hypergrid ──git tag v0.1.0──▶ GitHub Actions (Release) ──▶ GHCR :0.1.0 ◀──pull── server (tento repo, APP_VERSION=0.1.0)
```

| Súbor | Účel |
|---|---|
| `compose.yml` | služby `web` (nginx, v sieti `proxy`), `server` (ASP.NET Core), `db` (PostgreSQL 18); nič nemá `ports:` |
| `.env.example` | zoznam premenných; skutočný `.env` je iba na serveri (v `.gitignore`) |
| `deploy.sh` | stiahnuť image → záloha DB → spustiť → počkať na healthcheck |
| `backup.sh` | záloha DB (`pg_dump`) do `backups/` |

Cesta požiadavky: `internet → traefik (TLS) → web nginx :80 → /api, /hubs, /health → server :8080 → db`.
`server` a `db` sú iba v sieti `internal`.

Image (vznikajú workflowom `.github/workflows/release.yml` v repe `hypergrid` po pushnutí tagu `v*` na `main`):
- `ghcr.io/itjama/hypergrid-server:<verzia>`
- `ghcr.io/itjama/hypergrid-web:<verzia>`

---

## Prvá inštalácia na server

1. **Traefik** beží podľa `traefik-deploy` (vrátane `docker network create proxy` a DNS `*.app.iteo.sk`).
2. **Repo** do `/opt/hypergrid` (deploy key bez write access, rovnako ako pri `household-deploy`):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/hypergrid_deploy -N "" -C "hypergrid-server"
   cat >> ~/.ssh/config <<'CFG'
   Host github-hypergrid-deploy
     HostName github.com
     IdentityFile ~/.ssh/hypergrid_deploy
   CFG
   git clone git@github-hypergrid-deploy:itjama/hypergird-deploy.git /opt/hypergrid
   ```
3. **GHCR:** ak je server už prihlásený (`docker login ghcr.io` pre `household-deploy`, token `read:packages`),
   netreba nič — token platí pre všetky balíky účtu `itjama`.
4. **`.env`:**
   ```bash
   cd /opt/hypergrid && cp .env.example .env && nano .env
   ```
   `DB_PASSWORD`: `openssl rand -hex 32`, `GUEST_SIGNING_KEY`: `openssl rand -base64 48`.
5. **Spustenie:** `./deploy.sh 0.1.0` → prvý štart vytvorí tabuľky migráciami. Otvoriť `https://hypergrid.app.iteo.sk`.

## Nová verzia

1. V `hypergrid`: `main` ← `develop` (`git merge --ff-only`), `git tag v0.2.0 && git push origin main v0.2.0`.
2. GitHub → Actions → „Release“ zelený.
3. Na serveri: `cd /opt/hypergrid && git pull && ./deploy.sh 0.2.0` (pred spustením zálohuje DB).

Rollback: `./deploy.sh 0.1.0`. Migrácie DB sa návratom image nevrátia → ak nová verzia pridala migráciu,
obnov aj DB zo zálohy spred nasadenia.

## Zálohy a obnova

```bash
./backup.sh                                     # backups/db-<čas>.dump
```
Cron (`crontab -e`): `40 3 * * * /opt/hypergrid/backup.sh >> /opt/hypergrid/backups/backup.log 2>&1`.
Kópiu `backups/` pravidelne prenášať mimo VPS.

Obnova:
```bash
docker compose stop server
docker compose exec -T db pg_restore -U hypergrid -d hypergrid --clean --if-exists < backups/db-<čas>.dump
docker compose up -d --wait server && docker compose restart web
```

## Bežné príkazy

```bash
docker compose ps
docker compose logs -f server --tail=100
docker compose restart web          # po ručnom reštarte servera (nginx si drží IP z času štartu)
```

## Poznámky

- Názov GitHub repa je `hypergird-deploy` (preklep oproti `hypergrid`). Názov compose projektu je pevne
  `hypergrid-deploy`, takže volume (`hypergrid-deploy_pgdata`) nezávisia od priečinka.
- `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true`: server berie `X-Forwarded-*` od nginx vo `web`.
  nginx však posiela `X-Forwarded-Proto $scheme` (= `http`, lebo TLS končí v Traefiku) — kým to nevadí
  (server negeneruje absolútne URL ani nepresmerováva na HTTPS); ak by vadilo, upraviť `web/nginx.conf`.
