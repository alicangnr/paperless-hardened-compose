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
