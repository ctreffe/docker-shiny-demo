# docker-shiny-demo

[English version](README.md)

Eine minimale R/Shiny-Anwendung, die Docker-Containerisierung, den Import von
GitHub nach GitLab und CI/CD-Deployment über eine verwaltete Hosting-Plattform demonstriert.

## Projekt und Ziel

Das Ziel ist, den gesamten Weg vom Anwendungsquellcode zu einem laufenden Container
verständlich zu machen. Sie können die Demo lokal ausführen, ihren Begrüßungstext
über eine Umgebungsvariable ändern und dieselbe Anwendung in einem GitLab-Build-
und Deployment-Workflow verfolgen. Die Code- und Konfigurationsdateien enthalten
englische Kommentare, die die Schritte und ihren Zweck erklären.

GitHub ist die maßgebliche Quelle für die gepflegten Dateien. Die Hosting-Admins
importieren das öffentliche Repository in die Gruppe **Gemi** (Namespace `gemi`)
auf `gitlab.gwdg.de`. Nur die Hosting-Admins können in dieser Gruppe Projekte anlegen.
Ein optionaler GitLab-Job kopiert später neue GitHub-Commits in das GitLab-Repository.
Die Anwendung benötigt weder GitHub Actions noch eine GitHub-Container-Registry.

Die Demo hat eine interaktive Webseite. Ein Schieberegler wählt eine Zahl von 1
bis 10; der Server berechnet ihr Quadrat. Die Seite zeigt außerdem einen
konfigurierbaren Begrüßungstext. Der Healthcheck ruft diese Seite unter `/` ab;
es gibt keinen separaten `/health`-Endpunkt. Die Demo hat keine Anmeldung,
Datenbank oder persistenten Benutzerdaten. Die Hosting-Admins konfigurieren den
öffentlichen Hostnamen, Reverse-Proxy, TLS und erforderliche
Zugriffsbeschränkungen separat.

GitHub ist für Ihre eigene Anwendung optional. Die Admins können stattdessen ein
leeres Projekt in **Gemi** anlegen, und Sie können dieselben Dateien direkt in
GitLab pflegen. Lassen Sie in diesem Fall die Synchronisation deaktiviert und
pushen Sie Release-Commits direkt nach GitLab. Dieses Beispiel dokumentiert den
GitHub-Weg zusammen mit den gemeinsamen Hosting-Schritten.

## Dateien

| Datei | Zweck |
|---|---|
| `app.R` | Shiny-Oberfläche, maskierter Begrüßungstext und reaktive Quadratberechnung |
| `requirements.R` | Direkte R-Paketanforderungen, beim Image-Build installiert/geprüft |
| `shiny-server.conf` | Eine Anwendung auf Port 3838 mit beschreibbaren Laufzeitpfaden unter `/tmp` |
| `Dockerfile` | Rocker-Image mit Shiny Server, einem Benutzer ohne Root-Rechte und einem HTTP-Healthcheck |
| `compose.yaml` | Lokaler Build und Zugriff über die Loopback-Schnittstelle des Rechners |
| `compose.hosting.yaml` | Hosting-Konfiguration mit dem externen Netzwerk `dockernet` |
| `.env.example` | Unbedenkliche Vorlage für die lokale Konfiguration |
| `.gitignore`, `.dockerignore` | Halten lokale Einstellungen und unnötige Dateien aus Git und dem Image heraus |
| `.gitattributes` | Erhält Linux-Zeilenenden in unter Windows bearbeiteten Skripten |
| `.gitlab-ci.yml` | Tests, optionale Synchronisation, Image-Build und Release-Regeln |
| `scripts/common.sh` | Gemeinsame Variablenprüfungen und temporäre Registry-Anmeldung |
| `scripts/build.sh` | Image bauen, Start testen und veröffentlichen; Registry-Digest erfassen |
| `scripts/deploy.sh` | Ziel prüfen, das erfasste Image deployen und das Backend verifizieren |
| `scripts/sync.sh` | GitHub-Commits nur dann nach GitLab kopieren, wenn ein Fast-Forward möglich ist |
| `scripts/start.sh` | Temporäre Konfiguration vorbereiten und Shiny Server starten |
| `scripts/restore-environment.R` | Öffentlichen Begrüßungstext im Startprofil jedes R-Workers wiederherstellen |
| `scripts/probe.R` | HTTP-Antwort der App prüfen, optional einschließlich des erwarteten Begrüßungstexts |
| `scripts/test.sh` | App-, CI-Skript- und Shell-Syntaxprüfungen ausführen |
| `tests/` | Tests für Anwendungsverhalten und CI-Skripte ohne echte Git-Pushes oder Deployments |
| `TROUBLESHOOTING.md` | Bestätigte Shiny-Laufzeit- und lokale Testprobleme mit ihren Lösungen |
| `LICENSE` | MIT-Lizenz |

## Lokal mit Docker ausführen

Sie benötigen Docker Desktop mit Linux-Containern oder Docker Engine unter Linux
und Docker Compose v2 mit Unterstützung für `up --wait --wait-timeout` und
`config --format json`. Starten Sie Docker, bevor Sie die Befehle ausführen.
Führen Sie sie im Verzeichnis dieses Repositorys aus.

1. Kopieren Sie die Beispieleinstellungen. In Windows PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

   Unter Linux oder macOS:

   ```sh
   cp .env.example .env
   ```

2. Öffnen Sie `.env` in einem Texteditor. Behalten Sie den vorgegebenen
   Begrüßungstext bei oder ändern Sie `GREETING_TEXT`. `APP_PORT=3838` wählt
   den lokalen Port.

3. Bauen und starten Sie den Container:

   ```sh
   docker compose up --build --detach --wait --wait-timeout 90
   ```

4. Öffnen Sie [die lokale Webseite](http://localhost:3838). Die Seite zeigt den
   Begrüßungstext und zunächst `4 squared is 16`. Bewegen Sie den Schieberegler auf
   7 und prüfen Sie, dass das Ergebnis zu `7 squared is 49` wird. Haben Sie
   `APP_PORT` geändert, verwenden Sie diesen Port in der URL. Sie können außerdem
   Zustand und Logs prüfen:

   ```sh
   docker compose ps
   docker compose logs --tail 100 app
   ```

5. Erzeugen Sie nach einer Änderung an `GREETING_TEXT` den Container neu:

   ```sh
   docker compose up --detach --force-recreate --wait --wait-timeout 90
   ```

   Laden Sie die Seite neu, um den neuen Text zu sehen. Eine Änderung an `.env`
   erfordert keinen Image-Neubau. Änderungen an `app.R`, der Serverkonfiguration,
   den Skripten oder den Abhängigkeiten erfordern einen Neubau.

6. Stoppen und entfernen Sie anschließend den lokalen Container und das Netzwerk
   dieser Demo:

   ```sh
   docker compose down
   ```

Der lokale Port ist an `127.0.0.1` gebunden; dieser Befehl veröffentlicht die Demo
daher nicht für andere Rechner. Die echte `.env` wird von Git ignoriert und ist
vom Image ausgeschlossen.

Das Image nutzt `rocker/shiny:4.6.1`. Shiny Server und seine R-Worker laufen als
Benutzer `shiny` mit einem schreibgeschützten Root-Dateisystem. Temporäre Dateien,
Sitzungslogs und Bookmark-Verzeichnisse liegen in einem 256 MB großen
`/tmp`-tmpfs und verschwinden beim Entfernen des Containers. Server- und
Anwendungsdiagnosen sind auch in `docker compose logs` verfügbar. Diese Demo
aktiviert kein persistentes Bookmarking.

`requirements.R` listet direkte Pakete auf; das Basisimage enthält Shiny bereits.
Es ist keine Paket-Lockdatei. Ergänzen Sie dort für eine Anwendung mit weiteren
Abhängigkeiten die benötigten Pakete und erwägen Sie einen `renv.lock`-Workflow.
Der versionierte Basisimage-Tag kann weiterhin Updates erhalten; das
GitLab-Release erfasst den Digest des fertig gebauten Images.

## So funktioniert die Umgebungsvariable

`.env.example` dokumentiert einen sicheren Wert. Ihre lokale `.env` liefert Werte
an Docker Compose. Der Block `environment` in `compose.yaml` reicht
`GREETING_TEXT` ausdrücklich an den Container weiter. Shiny Server startet
R-Worker mit einer reduzierten Umgebung. Deshalb speichert `scripts/start.sh`
nur diese öffentliche Einstellung in einer privaten Datei im tmpfs.
`scripts/restore-environment.R`, nach `/home/shiny/.Rprofile` kopiert, stellt sie
in jedem Worker wieder her. Die App liest sie dann mit
`Sys.getenv("GREETING_TEXT", unset = "Hello from the Shiny container!")`.

Die temporäre RDS-Datei speichert Daten statt erzeugtem R-Code und erhält
Anführungszeichen, Dollarzeichen und Zeilenumbrüche. Sie wird bei jedem
Containerstart neu angelegt. Ersetzen Sie diese ausdrückliche Einstellung nicht
durch einen Export aller CI-Variablen.

Auf GitLab liefert stattdessen eine CI/CD-Variable den Hosting-Wert. Das
Deployment-Skript löst `compose.hosting.yaml` auf und speichert die
Laufzeitkonfiguration auf dem Host. Diese gespeicherte Konfiguration enthält
den Begrüßungstext. Verwenden Sie für `GREETING_TEXT` nur öffentlichen Text;
die Webseite zeigt ihn allen Besuchern. Echte Secrets gehören in eine separat
geprüfte Secret-Konfiguration, niemals in dieses Repository oder Image.

## Optionaler Erstimport aus GitHub

Nur die Hosting-Admins können in **Gemi** (Namespace `gemi`) Projekte anlegen
oder importieren. Als Anwendungsverantwortlicher bitten Sie sie um den Import.
Sind Sie selbst Hosting-Admin, führen Sie die folgenden Schritte aus. Für dieses
Beispiel wird ein öffentliches GitLab-Projekt gewünscht, ebenso wie die
öffentliche GitHub-Quelle.

### Import anfragen

Schicken Sie den Hosting-Admins die folgenden Angaben und Ihren GitLab-Benutzernamen:

| Angabe | Wert für dieses Beispiel |
|---|---|
| Öffentliches Quellrepository | `https://github.com/ctreffe/docker-shiny-demo.git` |
| Quellbranch | `main`; den vorgesehenen letzten Commit vor dem Import abstimmen |
| Zielinstanz | `https://gitlab.gwdg.de` |
| Zielgruppe / Namespace | **Gemi** / `gemi` |
| Projektname und Slug | `docker-shiny-demo` |
| Sichtbarkeit | **Public** (öffentlich) |

Die Quell-URL muss auf das GitHub-Repository zeigen. Der Ziel-Namespace legt fest,
wo GitLab das neue Projekt anlegt; er ist nicht die Quell-URL.

### Importschritte für die Hosting-Admins

1. Öffnen Sie [gitlab.gwdg.de](https://gitlab.gwdg.de) und melden Sie sich mit Ihrem
   berechtigten Konto an. Bestätigen Sie, dass Sie Projekte in **Gemi** anlegen
   dürfen und der Zielprojektname verfügbar ist.
2. Öffnen Sie **Create new** (das Plus-Menü) und wählen Sie **New project/repository**.
   Wählen Sie **Import project**, dann **Repository by URL**. Bezeichnungen und
   Menüpositionen können je nach installierter GitLab-Version und Sprache der
   Oberfläche abweichen.
3. Tragen Sie unter **Git repository URL** die URL
   `https://github.com/ctreffe/docker-shiny-demo.git` ein. Lassen Sie die Felder
   für Benutzername und Passwort/Token der Quelle leer: Dieses Repository ist
   öffentlich, sein Import benötigt daher keine GitHub-Zugangsdaten.
4. Füllen Sie die Zielfelder wie folgt aus:

   | Feld | Wert |
   |---|---|
   | Project name | `docker-shiny-demo` |
   | Project URL / namespace | **Gemi** (`gemi`) auswählen, nicht den persönlichen Namespace |
   | Project slug / path | `docker-shiny-demo` |
   | Visibility level | **Public** (öffentlich), falls verfügbar; andernfalls Erstimport als **Private** abstimmen |

   Prüfen Sie, dass der resultierende Zielpfad `gemi/docker-shiny-demo` lautet.
   Fehlt **Gemi**, lassen Sie die Gruppenberechtigungen prüfen. Fehlt **Repository
   by URL**, fragen Sie die GitLab-Instanzadmins, ob diese Importquelle aktiviert
   werden kann. Klären Sie fehlende Namespace- oder Importberechtigungen,
   bevor Sie das Projekt anlegen. Ist **Public** nicht verfügbar, ist ein
   abgestimmter Erstimport als **Private** möglich; siehe den Sichtbarkeitshinweis unten.
5. Wählen Sie **Create project** und warten Sie, bis der Import abgeschlossen ist.
   Die erwartete Projektadresse ist `https://gitlab.gwdg.de/gemi/docker-shiny-demo`,
   sofern der vereinbarte Namespace und Slug verwendet werden. Diese Adresse ist
   ein Zielbeispiel, keine Bestätigung, dass das Projekt bereits existiert.
6. Öffnen Sie das Repository auf Branch `main` und vergleichen Sie die vollständige
   SHA des letzten Commits mit GitHub. Der URL-Import kopiert das Repository so,
   wie es während des Imports vorliegt; eine vorgesehene SHA in der Anfrage
   fixiert diesen Stand nicht. Hat sich GitHub inzwischen geändert, stimmen Sie
   ab, welche Revision akzeptiert werden soll. Prüfen Sie, dass `app.R`,
   `Dockerfile`, `.env.example`, `.gitlab-ci.yml`, `scripts/` und beide Readmes
   vorhanden sind. Pipeline-Dateien und Skripte sind bereits enthalten.
7. Gewähren Sie dem Anwendungsverantwortlichen die vereinbarte Projektmitgliedschaft
   und schicken Sie ihm die Projekt-URL. Prüfen Sie den importierten CI-Code und
   stellen Sie einen geeigneten Linux-Runner mit Docker-Executor für `test-app`
   bereit. Behalten Sie für den ersten Test `HOSTING_ENABLED=false`,
   `SYNC_ENABLED=false` und `RUN_SYNC=false` bei; bestätigen Sie, dass geerbte
   Gruppen- oder Projektvariablen diese Werte nicht überschreiben.
8. Öffnen Sie **Build > Pipelines** und prüfen Sie eine eventuell vorhandene
   Pipeline für diesen Commit. Existiert keine, wählen Sie **New pipeline**
   (in manchen Versionen **Run pipeline**), wählen Sie `main`, behalten Sie
   `RUN_SYNC=false` bei und starten Sie die Pipeline. Bei deaktiviertem Hosting
   und deaktivierter Synchronisation wird nur `test-app` ausgewählt. Öffnen Sie
   dessen Log und prüfen Sie, dass er erfolgreich durchläuft. Bei einem wartenden
   Job müssen die Admins die Runner-Verfügbarkeit prüfen; ein abgeschlossener
   Import allein bestätigt nicht die Funktion von CI.

### Wenn das Projekt zunächst privat importiert wurde

Beim parallelen Flask-Beispiel wurde **Public** beim Import auf
`gitlab.gwdg.de` nicht angeboten; dieses Projekt wurde deshalb zunächst als
**Private** angelegt. Der Grund für die fehlende Option ist noch nicht bestätigt.
Dieselbe Einschränkung kann für dieses Shiny-Projekt gelten. Ein Import muss
nicht allein deshalb wiederholt werden, weil sich die Sichtbarkeit später ändern kann.

Bitten Sie einen Gruppen-Owner, die Sichtbarkeit von **Gemi** und gegebenenfalls
übergeordneten Gruppen zu prüfen. Ein Projekt kann nicht öffentlicher sein als
seine umgebenden Gruppen: Private Gruppen erlauben nur private Projekte,
interne Gruppen erlauben keine öffentlichen Projekte. Schränkt die GitLab-Instanz
öffentliche Sichtbarkeit ein, müssen die GWDG-Instanzadmins diese Einschränkung
klären; ein Gruppen-Owner kann sie nicht übergehen.

Sobald die erforderliche Gruppensichtbarkeit und die Instanzberechtigungen es
zulassen, kann ein Projekt-Owner unter **Settings > General > Visibility, project
features, permissions** die Einstellung **Project visibility** auf **Public**
setzen und die Änderung speichern. Eine öffentliche Gruppe macht ihre vorhandenen
privaten Projekte nicht automatisch öffentlich.

Solange das Projekt privat bleibt, können berechtigte Mitglieder seine Dateien
und die Testpipeline weiter prüfen. Die öffentliche Repository-Sichtbarkeit ist
von der späteren Hostnamen- und Webzugriffskonfiguration der Anwendung getrennt.

### Was der Import bewirkt

Den Erstimport führt GitLab selbst aus, kein Runner. Er kopiert das Git-Repository
einmal einschließlich seiner Historie, richtet keine kontinuierliche
Synchronisation ein und kopiert keine GitHub-Issues und Pull Requests.
Hosting-Einrichtung und optionale spätere Synchronisation sind separate Schritte,
die weiter unten beschrieben werden.

Anwendungsverantwortliche prüfen nach Erhalt des Zugriffs die importierte Revision
und die Dateien. Die Hosting-Admins prüfen den importierten CI-Code, bevor sie
Zugriff auf Deployment-Runner oder Zugangsdaten freigeben. Eine erfolgreiche erste
Testpipeline bestätigt den Test-Job; sie deployt die Anwendung nicht.

Das Verfahren folgt der [GitLab-Dokumentation zum URL-Import](https://docs.gitlab.com/user/import/third_party_systems/repo_by_url/),
den [Regeln zur Projektsichtbarkeit](https://docs.gitlab.com/user/public_access/) und
der [Dokumentation zu manuellen Pipelines](https://docs.gitlab.com/ci/pipelines/#run-a-pipeline-manually).
Die Verfügbarkeit der Importoption und die angemeldete GWDG-Oberfläche müssen
die Hosting-Admins weiterhin auf der tatsächlichen Instanz bestätigen.

## Hosting-Einrichtung durch die Admins

Bestätigen Sie vor dem Aktivieren des Hostings Runner-Executors, Registry und
Berechtigungen auf der tatsächlichen GitLab-Instanz. Test- und Sync-Jobs erwarten
einen geeigneten Linux-Runner mit Docker-Executor. Build- und Deploy-Jobs erwarten
einen Linux-Runner mit **Shell-Executor**, der mit `apps.psych` und `production`
getaggt ist und auf dem Bash, Git, `python3`, Docker Engine, Docker Compose v2
und GNU `realpath` bereits verfügbar sind. Diese Jobs nutzen den Docker-Daemon
dieses Hosts; `image:` eines Jobs konfiguriert keinen Shell-Executor. Die
Tag-Namen allein belegen diese Fähigkeiten nicht.

Aktivieren Sie die Container Registry des Projekts und schützen Sie den
Default-Branch. Konfigurieren Sie, wer ihn ändern oder seine Pipelines starten
darf. Aktivieren Sie **Prevent outdated deployment jobs** in den
GitLab-Deployment-Einstellungen. Konfigurieren Sie die Kontrollen der Umgebung
`production`, soweit die installierte Edition sie unterstützt. Wählen Sie ein
eigenes Anwendungsverzeichnis unterhalb des vorhandenen Deployment-Stammverzeichnisses
der Plattform und bestätigen Sie, dass `dockernet` existiert. Der Deployment-Job
erstellt fehlende Anwendungsverzeichnisse selbst; für jede neue Anwendung ist
keine manuelle Verzeichnisanlage erforderlich. Der Runner muss bereits unter
dem gewählten Stammverzeichnis Verzeichnisse anlegen und in ein vorhandenes
Anwendungsverzeichnis schreiben dürfen. Das gehört zur gemeinsamen Plattform-Einrichtung.

Fügen Sie die folgenden Variablen unter **Settings > CI/CD > Variables** hinzu.
Hosting- und Sync-Einstellungen müssen geschützt und für ihre Jobs verfügbar
sein. Verwenden Sie in diesem Beispiel den Umgebungsbereich **All**: Build-
und Sync-Jobs deklarieren die Umgebung `production` nicht. Überschreiben Sie
weder vordefinierte `CI_*`-Variablen noch die Release-Artefaktvariablen
`APP_IMAGE`, `RELEASE_COMMIT`, `RELEASE_PIPELINE_ID`.

| Variable | Wert oder Zuständigkeit |
|---|---|
| `HOSTING_ENABLED` | `true` nach Prüfung der Hosting-Einrichtung; Vorgabe ist `false` |
| `GREETING_TEXT` | Öffentlicher Begrüßungstext, etwa `Hello from GitLab!`; die Anwendung hat eine Vorgabe |
| `DEPLOY_ROOT` | Vorhandenes, von den Admins freigegebenes Stammverzeichnis, etwa `/opt/docker/apps`; niemals `/` |
| `DEPLOY_DIR` | Anwendungsverzeichnispfad strikt unterhalb des Stammverzeichnisses, etwa `/opt/docker/apps/docker-shiny-demo`; der Job legt es bei Bedarf an |
| `APP_CONTAINER_NAME` | Von den Admins zugewiesener eindeutiger Containername, etwa `docker-shiny-demo` |
| `APP_NETWORK_ALIAS` | Von den Admins zugewiesener eindeutiger Backend-Name auf `dockernet`, etwa `docker-shiny-demo` |
| `SYNC_ENABLED` | `true` nur dann, wenn spätere GitHub-Updates gewünscht sind; Vorgabe ist `false` |
| `GITLAB_SYNC_TOKEN` | Maskierter, geschützter Access Token mit `write_repository`, dessen Konto auf den geschützten Default-Branch pushen darf |

GitLab stellt `CI_REGISTRY`, `CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER` und
`CI_REGISTRY_PASSWORD` für den Registry-Zugriff bereit. Die Skripte halten die
Registry-Anmeldung des Jobs temporär. Die Admins konfigurieren den gemeinsamen
Proxy für den Zugriff auf `APP_NETWORK_ALIAS:3838` und behandeln DNS, TLS und
Zugriffsbeschränkungen separat. Die Hosting-Compose-Datei veröffentlicht
keinen Host-Port. Der Reverse-Proxy muss die interaktiven Shiny-Verbindungen
einschließlich WebSocket-Upgrades unterstützen.

Bevorzugen Sie für die Synchronisation einen Project Access Token, falls die
Instanz ihn unterstützt; verwenden Sie andernfalls einen dedizierten Personal
Access Token mit dem genannten Scope und angemessener Ablaufzeit. Verwenden
Sie für den Push dieses Beispiels nicht `CI_JOB_TOKEN`: Seine Pushes lösen
keine Folgepipeline aus. Pflegen Sie Anwendungsänderungen auf GitHub.
Nur auf GitLab vorhandene Commits würden die beiden Historien auseinanderlaufen
lassen und die Synchronisation stoppen.

## Optionale spätere Updates über einen Runner

Nachdem die Admins die Synchronisation aktiviert und ihren Token konfiguriert haben:

1. Prüfen und pushen Sie die vorgesehenen Änderungen auf den Default-Branch auf GitHub.
2. Öffnen Sie in GitLab **Build > Pipelines** und starten Sie eine neue Pipeline
   auf dem geschützten Default-Branch. Setzen Sie die Pipeline-Variable `RUN_SYNC`
   auf `true`.
3. Der Sync-Job holt `GITHUB_REPO_URL` und `GITHUB_BRANCH` ab (standardmäßig
   dieses Repository und `main`). Erweitern neue Commits die aktuelle GitLab-Historie,
   pusht er sie ohne Merge-Commit oder Force-Push. Stimmen die Historien überein,
   tut er nichts. Sind sie auseinander gelaufen, schlägt er fehl und die Admins
   müssen den Unterschied auflösen.
4. Ein erfolgreiches Update startet eine **neue Push-Pipeline** für den
   importierten Commit. Verfolgen Sie diese Pipeline für Tests, Build und ein
   mögliches Release. Die Sync-Pipeline selbst baut oder deployt den alten Checkout nicht.

Ein optionaler Zeitplan kann denselben Sync-Job mit `RUN_SYNC=true` starten.
Vereinbaren Sie dies separat mit den Admins. Ein neu synchronisierter letzter
Commit mit `[deploy]` kann die Folgepipeline zum Deployment veranlassen,
wenn Hosting aktiviert ist. Ein Zeitplan umgeht keine Prüfung und ändert
die Release-Regel nicht.

Der Sync-Job folgt einem Branch. Er spiegelt weder Tags noch andere Branches,
GitHub-Issues, Pull Requests oder Löschungen. War ein Push erfolgreich, aber
die Folgepipeline konnte nicht starten, starten Sie manuell eine normale
Pipeline auf dem importierten Default-Branch-Commit mit `RUN_SYNC=false`;
wiederholen Sie keinen davon unabhängigen Release-Commit.

## Build und Release-Regel

Normale Branch-Pipelines führen die Tests aus. Bei aktiviertem Hosting bauen
Push-Pipelines oder manuell gestartete Pipelines auf dem geschützten
Default-Branch außerdem ein Image, testen seinen Start und veröffentlichen
es in der GitLab Container Registry. Das Deployment erfordert zusätzlich
den exakten Teilstring **`[deploy]`** in der Nachricht dieses Commits.
Die Übereinstimmung unterscheidet Groß- und Kleinschreibung. `deploy`,
`[deployment]`, andere Branches, Tags, Merge-Request-Pipelines und die
Sync-Pipeline wählen den Deployment-Job nicht aus.

Prüfen Sie für ein Release die vollständigen Quellen, pushen Sie dann einen
Default-Branch-Commit mit einer Nachricht wie `Release demo [deploy]` nach
GitHub und starten Sie den Sync-Job. Die neue GitLab-Pipeline testet und baut
diese importierte Revision vor dem Deployment.

Das Deployment nutzt die unveränderliche `@sha256:`-Image-Referenz des Builds
und prüft deren Commit- und Pipeline-Labels. Es lehnt einen veralteten Branch-Stand
oder eine ältere Pipeline als das letzte erfolgreiche Deployment ab.
Das Skript prüft den aufgelösten Zielpfad vor Schreibzugriffen, erstellt ein
fehlendes Anwendungsverzeichnis und startet das Image über Compose. Es wartet
auf den Healthcheck und prüft den HTTP-Zugriff aus `dockernet`. Neue Verzeichnisse
sind nur für den Runner-Benutzer zugänglich (Modus `0700`); vorhandene Verzeichnisse
behalten ihre Rechte und Inhalte. Der Job legt das Plattform-Stammverzeichnis
nicht an und ändert weder Eigentümer noch Rechte vorhandener Verzeichnisse.
Fehlt dem Runner der Zugriff, schlägt er mit einer eindeutigen Meldung fehl;
ein Plattformadmin muss dann die gemeinsamen Berechtigungen korrigieren.

Anwendungsverantwortliche können den Container daher ohne einen separaten
manuellen Schritt zur Anlage des Anwendungsverzeichnisses deployen. Sobald er
auf dem Host läuft, nehmen die Hosting-Admins das Backend ab und konfigurieren
öffentliches Routing, DNS, TLS und gegebenenfalls Zugriffsbeschränkungen.

Nach der Abnahme enthält `DEPLOY_DIR/compose.json` die aufgelösten
Laufzeiteinstellungen; `DEPLOY_DIR/release.txt` erfasst Pipeline-ID, Commit und
Image-Digest. Anwendungscode liegt im Image und wird nicht aus dem
Runner-Checkout gemountet. Das Skript löscht keine Host-Daten oder Secrets.
Schlägt der Start oder die Backend-Prüfung fehl, schlägt der Job fehl und
behält die Kandidatenkonfiguration zur Diagnose. Der laufende Container
kann bereits geändert worden sein; es gibt keinen automatischen Rollback.
Die Admins prüfen den Dienst vor einer Wiederholung und behandeln eine
Wiederherstellung ausdrücklich.

Die Dateien sind eine Lehrimplementierung. Import, Runner-Kompatibilität,
Image-Build, Deployment, öffentliches Routing und Wiederherstellung müssen
auf der tatsächlichen GWDG-/Hosting-Umgebung geprüft werden, bevor sie
als funktionierender produktiver Workflow gelten können.

## Tests und Fehlerbehebung

GitLab führt vier R-Verhaltensprüfungen, zehn Python-Skripttests und
Shell-Syntaxprüfungen aus. Die R-Tests prüfen den vorgegebenen und den über die
Umgebung gesetzten Begrüßungstext, HTML-Maskierung und reaktive Regleränderungen
mit `shiny::testServer`. HTTP-Prüfungen kontrollieren die gerenderte Seite und
ihr Eingabeelement; ein gesunder Container allein bestätigt nicht die Funktion
der interaktiven Browserverbindung. Bewegen Sie zur Abnahme den Schieberegler im
Browser und prüfen Sie das aktualisierte Ergebnis.

Führen Sie dieselben Prüfungen lokal im separaten Testimage aus:

```sh
docker build --target tests --tag docker-shiny-demo:tests .
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,exec,nosuid,size=256m docker-shiny-demo:tests
```

Das Testimage ergänzt `testthat` und die Testwerkzeuge. Das vorgegebene
Laufzeitimage kopiert weder Tests noch CI-Skripte. Nur das temporäre Verzeichnis
des Testcontainers ist ausführbar: Das simulierte Git-Programm benötigt dies.
Die App-Container behalten `noexec` auf `/tmp` bei.

Die Skripttests nutzen ein simuliertes Git-Programm und pushen niemals oder
legen echte Repositories an. Tests für Deployment-Verzeichnisse laufen unter
Linux/POSIX mit Bash und GNU `realpath`; sie prüfen echte Verzeichnisanlage und
Pfadgrenzen in temporären Ordnern. Berechtigungstests benötigen einen Benutzer
ohne Root-Rechte, wie er im lokalen Testimage verwendet wird.
Siehe die [bestätigten Lösungen](TROUBLESHOOTING.md) für die Shiny-spezifischen
Laufzeitdetails.

| Symptom | Was zu prüfen ist |
|---|---|
| Docker kann keine Verbindung herstellen | Docker Desktop starten und Linux-Container auswählen |
| Lokaler Port wird bereits verwendet | `APP_PORT` in `.env` ändern und den Container neu erzeugen |
| Begrüßungstext hat sich nicht geändert | Container nach einer Änderung an `.env` neu erzeugen |
| GitLab-Job wartet auf Ausführung | Runner-Verfügbarkeit, Executor, Tags und Zugriff auf geschützte Branches bestätigen |
| Nur Tests laufen | Hosting ist standardmäßig deaktiviert; Admins müssen es konfigurieren und aktivieren |
| Sync meldet auseinander gelaufene Historien | Beide Seiten erhalten und die Admins fragen; keinen Force-Push ausführen |
| Kein Deploy-Job erscheint | Exakten Marker, Default-/geschützten Branch, Hosting-Schalter und Pipeline-Quelle prüfen |
| Deployment schlägt fehl | Fehler und Logs des Jobs lesen; die Admins müssen den laufenden Dienst und die Kandidatenkonfiguration prüfen |

## Referenzen und Lizenz

- [Rocker-Shiny-Images](https://rocker-project.org/images/versioned/shiny.html)
- [Shiny-Server-Konfiguration](https://docs.posit.co/shiny-server/)
- [Implementierung der R-Worker-Umgebung in Shiny Server](https://github.com/rstudio/shiny-server/blob/master/lib/worker/app-worker.js)
- [Tests der Shiny-Serverfunktion](https://shiny.posit.co/r/reference/shiny/latest/testserver.html)
- [R-Startprofile](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Startup.html)
- [Docker-Compose-Umgebungsinterpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)
- [GitLab-Import über eine Git-URL](https://docs.gitlab.com/user/import/third_party_systems/repo_by_url/)
- [GitLab-CI/CD-Variablen](https://docs.gitlab.com/ci/variables/)
- [GitLab-Job-Token-Verhalten beim Push](https://docs.gitlab.com/ci/jobs/ci_job_token/#allow-git-push-requests-to-your-project-repository)
- [GitLab-Deployment-Sicherheit](https://docs.gitlab.com/ci/environments/deployment_safety/)

Dieses Projekt wird unter der [MIT-Lizenz](LICENSE) bereitgestellt.
