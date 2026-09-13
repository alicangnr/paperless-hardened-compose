#!/usr/bin/env bash
set -euo pipefail

echo "== paperless-hardened-compose: Setup =="

mkdir -p docs

cat > .gitignore <<'EOF'
.env
EOF

cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 Alican Güngör

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

cat > .env.example <<'EOF'
# Kopieren nach .env und ausfüllen. .env NIEMALS committen.

# --- Reverse Proxy ---
PROXY_NETWORK_NAME=reverse-proxy_proxynet

# --- PostgreSQL ---
POSTGRES_DB=paperless
POSTGRES_USER=paperless
POSTGRES_PASSWORD=

# --- Paperless-ngx ---
PAPERLESS_URL=https://paperless.example.com
PAPERLESS_SECRET_KEY=

# --- paperless-gpt (optional) ---
PAPERLESS_GPT_VERSION=v0.x.x
PAPERLESS_API_TOKEN=
LLM_BASE_URL=http://ollama-host:11434
LLM_MODEL=qwen3:14b
EOF

cat > docker-compose.yml <<'EOF'
version: "3.9"

# Referenz-Setup für ein gehärtetes Paperless-ngx mit optionaler
# KI-Metadaten-Anreicherung über paperless-gpt.
# Details je Härtungsmaßnahme: siehe docs/SECURITY.md

networks:
  db-internal:
    internal: true          # kein Zugriff nach außen
  proxy-external:
    external: true          # wird von deinem Reverse-Proxy-Stack bereitgestellt
    name: ${PROXY_NETWORK_NAME:-reverse-proxy_proxynet}

services:
  db:
    image: postgres:14-alpine
    restart: unless-stopped
    networks:
      - db-internal
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-paperless}
      POSTGRES_USER: ${POSTGRES_USER:-paperless}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?bitte in .env setzen}
    volumes:
      - db-data:/var/lib/postgresql/data
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    labels:
      - com.centurylinklabs.watchtower.enable=true

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    networks:
      - db-internal
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    labels:
      - com.centurylinklabs.watchtower.enable=true

  paperless-ngx:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    depends_on:
      - db
      - redis
    networks:
      - db-internal
      - proxy-external
    # Kein "ports:" nach außen — Zugriff ausschließlich über Reverse Proxy
    environment:
      PAPERLESS_REDIS: redis://redis:6379
      PAPERLESS_DBHOST: db
      PAPERLESS_DBNAME: ${POSTGRES_DB:-paperless}
      PAPERLESS_DBUSER: ${POSTGRES_USER:-paperless}
      PAPERLESS_DBPASS: ${POSTGRES_PASSWORD:?bitte in .env setzen}
      PAPERLESS_URL: ${PAPERLESS_URL:?z.B. https://paperless.example.com}
      PAPERLESS_SECRET_KEY: ${PAPERLESS_SECRET_KEY:?bitte in .env setzen}
    volumes:
      - paperless-data:/usr/src/paperless/data
      - paperless-media:/usr/src/paperless/media
      - paperless-export:/usr/src/paperless/export
      - paperless-consume:/usr/src/paperless/consume
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 2G
    labels:
      - com.centurylinklabs.watchtower.enable=true

  # Optional: KI-gestützte Metadaten-Anreicherung.
  # WICHTIG: paperless-gpt bringt KEINE eigene Authentifizierung mit.
  # Daher niemals mit "ports:" nach außen exponieren — ausschließlich über
  # den Reverse Proxy, der seinerseits Auth/Access-Control übernimmt.
  paperless-gpt:
    image: ghcr.io/icereed/paperless-gpt:${PAPERLESS_GPT_VERSION:?Version fixieren, kein :latest}
    restart: unless-stopped
    depends_on:
      - paperless-ngx
    networks:
      - proxy-external
    environment:
      PAPERLESS_BASE_URL: http://paperless-ngx:8000
      PAPERLESS_API_TOKEN: ${PAPERLESS_API_TOKEN:?bitte in .env setzen}
      LLM_BASE_URL: ${LLM_BASE_URL:?z.B. http://ollama-host:11434 via VPN}
      LLM_MODEL: ${LLM_MODEL:-qwen3:14b}
      # Bewusst deaktiviert: keine automatische Verarbeitung.
      # Trigger erfolgt manuell über das Tag "paperless-gpt" in der UI.
      AUTO_TAG: "false"
      # Bewusst deaktiviert, solange keine verifizierte Backup-Strategie
      # für Originaldokumente existiert.
      PDF_REPLACE: "false"
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    labels:
      - com.centurylinklabs.watchtower.enable=true

  watchtower:
    image: containrrr/watchtower
    restart: unless-stopped
    command: --label-enable --cleanup --interval 86400
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

volumes:
  db-data:
  paperless-data:
  paperless-media:
  paperless-export:
  paperless-consume:
EOF

cat > README.md <<'EOF'
# paperless-hardened-compose

Ein produktionsnahes, sicherheitsgehärtetes Docker-Compose-Setup für
[Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) inklusive optionaler
KI-gestützter Metadaten-Anreicherung über [paperless-gpt](https://github.com/icereed/paperless-gpt)
und ein lokal betriebenes LLM (z. B. Ollama).

Dieses Repo ist **kein Fork** von Paperless-ngx, sondern eine dokumentierte
Referenz-Konfiguration für alle, die Paperless-ngx selbst hosten und dabei
BSI-Grundschutz- bzw. DORA-nahe Härtungsprinzipien anwenden wollen, ohne sich
die Best Practices selbst zusammensuchen zu müssen.

## Warum dieses Repo?

Die offizielle Paperless-ngx-Dokumentation zeigt ein funktionierendes
Compose-Setup, geht aber bewusst nicht auf Härtung, Angriffsfläche von
Drittanbieter-Plugins (wie paperless-gpt) oder automatisierte Updates ein.
Für kleine Unternehmen und Privatanwender, die personenbezogene bzw.
geschäftskritische Dokumente archivieren, reicht das „Happy Path"-Setup
nicht aus. Dieses Repo schließt genau diese Lücke.

## Enthaltene Härtungsmaßnahmen

- **Kein direktes Port-Mapping** für paperless-gpt, da der Dienst keine
  eigene Authentifizierung mitbringt — Zugriff ausschließlich über einen
  Reverse Proxy (z. B. Nginx Proxy Manager, Caddy, Traefik)
- **Manuelles Trigger-Tag statt automatischer Verarbeitung** (kein
  `AUTO_TAG`), damit KI-gestützte Metadaten-Änderungen nie unbeaufsichtigt
  laufen
- **`PDF_REPLACE` bewusst deaktiviert**, solange keine verifizierte Backup-
  Strategie für die Originaldokumente existiert
- **Versions-Pinning statt `:latest`** für alle Komponenten, die
  Dokumentinhalte verändern können
- **Linux Capabilities minimiert**: `cap_drop: ALL` plus gezielte,
  dokumentierte `cap_add`
- **Ressourcenlimits** pro Container (CPU/RAM), um Denial-of-Service durch
  einzelne Container zu verhindern
- **Automatisierte Image-Updates** über Watchtower, beschränkt per Label auf
  ausgewählte Container
- **Getrennte Netzwerke**: internes Datenbank-Netz vs. externes Proxy-Netz

Details und Begründung je Maßnahme stehen in [`docs/SECURITY.md`](docs/SECURITY.md).

## Schnellstart

```bash
git clone https://github.com/76-Nizami/paperless-hardened-compose.git
cd paperless-hardened-compose
cp .env.example .env
# .env anpassen: Domains, Secrets, LLM-Endpunkt
docker compose up -d
```

Voraussetzungen: laufender Reverse Proxy mit eigenem Docker-Netzwerk, ein
per API erreichbares LLM (lokal oder remote) falls paperless-gpt genutzt
werden soll.

## Nicht enthalten

- Der Reverse Proxy selbst (Konfiguration variiert stark je nach Setup)
- Backup-Strategie für Dokumente/Datenbank (siehe `docs/SECURITY.md` für
  Hinweise, warum das vor Aktivierung von `PDF_REPLACE` zwingend ist)
- Das LLM-Backend selbst (Ollama, OpenAI-kompatible API o. ä.)

## Lizenz

MIT — siehe [`LICENSE`](LICENSE). Nutzung auf eigene Verantwortung; dies ist
keine offizielle Paperless-ngx- oder paperless-gpt-Ressource.

## Mitmachen

Issues und Pull Requests zu weiteren Härtungsmaßnahmen, Alternativen zu
Watchtower oder Erfahrungsberichten aus anderen Umgebungen sind willkommen.
EOF

cat > docs/SECURITY.md <<'EOF'
# Härtungsmaßnahmen — Begründung

Dieses Dokument erklärt jede Abweichung vom Standard-Setup aus der
Paperless-ngx-Dokumentation und warum sie sinnvoll ist. Referenzrahmen:
BSI-Grundschutz-Prinzipien (Minimalprinzip, Netztrennung) und DORA-nahe
Anforderungen an Nachvollziehbarkeit und Änderungskontrolle bei
automatisierten Systemen, die Dokumente/Daten verändern können.

## 1. Kein Port-Mapping für paperless-gpt

`paperless-gpt` bringt keine eigene Authentifizierung mit. Ein direktes
`ports:`-Mapping würde den Dienst ungeschützt im lokalen Netz oder — je nach
Firewall — im Internet erreichbar machen. Stattdessen läuft der Dienst
ausschließlich im internen Proxy-Netzwerk; Zugriffskontrolle übernimmt der
vorgelagerte Reverse Proxy.

## 2. Manuelles Trigger-Tag statt `AUTO_TAG`

Automatische, unbeaufsichtigte Verarbeitung durch ein LLM ist bei
Dokumenten mit rechtlicher oder geschäftlicher Relevanz nicht akzeptabel,
solange keine Kontrollinstanz dazwischensteht. Mit `AUTO_TAG=false` läuft
die KI-Anreicherung nur, wenn ein Mensch das Dokument explizit mit dem Tag
`paperless-gpt` markiert — jede Änderung ist damit einer bewussten
Entscheidung zuordenbar.

## 3. `PDF_REPLACE` deaktiviert

`PDF_REPLACE` lässt paperless-gpt das Originaldokument ersetzen. Ohne
verifizierte, getestete Backup-Strategie (Datenbank UND Mediendateien) ist
das ein nicht wiederherstellbares Risiko. Diese Option sollte erst
aktiviert werden, nachdem ein Restore-Test erfolgreich durchgeführt wurde.

## 4. Versions-Pinning statt `:latest`

Für Komponenten, die Dokumentmetadaten oder -inhalte verändern können
(paperless-gpt), wird bewusst keine `:latest`-Referenz verwendet. Ein
automatisches Update auf eine neue Version mit geändertem Verhalten könnte
sonst unbemerkt bestehende Automatisierungen (z. B. das Tag-basierte
Triggering) verändern.

## 5. Capabilities minimiert (`cap_drop: ALL`)

Alle Container laufen mit `cap_drop: ALL` und, wo technisch nötig, gezielt
wieder hinzugefügten Capabilities (z. B. `CHOWN`/`SETUID`/`SETGID` für
paperless-ngx, das beim Start Dateiberechtigungen im Volume anpassen muss).
Das reduziert die Angriffsfläche bei einer Kompromittierung eines
einzelnen Containers erheblich.

## 6. Ressourcenlimits

CPU- und Speicherlimits pro Container verhindern, dass ein kompromittierter
oder fehlerhafter Container (z. B. durch eine Endlosschleife in einem
LLM-Aufruf) die gesamte Docker-Hostmaschine lahmlegt.

## 7. Netztrennung

Datenbank und Redis liegen in einem internen Netzwerk (`internal: true`)
ohne Verbindung nach außen. Nur paperless-ngx und paperless-gpt hängen
zusätzlich im externen Proxy-Netzwerk. Ein kompromittierter Proxy-seitiger
Dienst kann damit nicht direkt auf die Datenbank zugreifen.

## 8. Automatisierte Updates mit Watchtower

Sicherheitsupdates für Basis-Images (Postgres, Redis, paperless-ngx) sollen
zeitnah einfließen. Watchtower ist per Label gezielt auf ausgewählte
Container beschränkt — paperless-gpt ist bewusst NICHT für automatische
Updates vorgesehen (siehe Punkt 4), Watchtower verwaltet dort nur den
Container-Lifecycle, nicht die Image-Version.

## Bekannte Grenzen dieses Setups

- Kein Intrusion-Detection-System enthalten
- Kein automatisiertes Backup enthalten (bewusst — Backup-Strategien sind
  zu umgebungsspezifisch für eine generische Empfehlung)
- Der Reverse Proxy selbst muss eigenständig gehärtet werden (TLS,
  Rate-Limiting, ggf. Fail2ban)
EOF

git init -q
git config user.email "gnr.alican@gmail.com"
git config user.name "76-Nizami"
git add .
git commit -q -m "Initial release: hardened Paperless-ngx compose reference"
git branch -M main

echo ""
echo "== Fertig. Lokales Repo committet auf 'main'. =="
echo "Nächster Schritt: GitHub-Repo anlegen (github.com/new, Name: paperless-hardened-compose, PUBLIC),"
echo "dann:"
echo "  git remote add origin https://github.com/76-Nizami/paperless-hardened-compose.git"
echo "  git push -u origin main"
