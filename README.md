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
