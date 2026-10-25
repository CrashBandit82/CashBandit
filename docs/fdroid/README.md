# F-Droid

`at.macrobandit.cashbandit.yml` ist die Metadatendatei für [fdroiddata](https://gitlab.com/fdroid/fdroiddata)
(`metadata/at.macrobandit.cashbandit.yml`). `commit` muss der volle Hash des getaggten Release-Commits sein.

Voraussetzungen im Repo (erfüllt): nur freie Abhängigkeiten, keine Google-Dienste/Tracker, kein
`INTERNET` im Release, `dependenciesInfo` abgeschaltet, SQLite aus dem Quellcode (`tools/fetch-sqlite.sh`),
Flutter fest auf 3.47.7, Fastlane-Metadaten unter `fastlane/metadata/android/`.

## Merge Request einreichen

1. Auf GitLab `fdroid/fdroiddata` forken (öffentlich, Branch nicht geschützt).
2. Branch `cashbandit` anlegen, Datei nach `metadata/at.macrobandit.cashbandit.yml` kopieren.
3. Lokal prüfen: `fdroid lint at.macrobandit.cashbandit` und `fdroid rewritemeta at.macrobandit.cashbandit`
   (optional `fdroid build -v -l at.macrobandit.cashbandit`).
4. Commit „New app: CashBandit“, pushen, Merge Request gegen `fdroid/fdroiddata:master` mit dem Titel
   **New app: CashBandit** und der Vorlage „App inclusion“ öffnen; Checkliste ausfüllen.
5. Auf Rückfragen der Reviewer reagieren; nach dem Merge erkennt F-Droid neue Tags `vX.Y.Z` selbst.
