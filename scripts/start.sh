#!/usr/bin/env bash
# Create only disposable runtime directories, then let Docker signal the server.
set -euo pipefail
umask 077
mkdir -p /tmp/shiny-server/bookmarks
# Shiny Server filters the R worker's environment. Save just this public setting
# in tmpfs; /home/shiny/.Rprofile restores it before the worker loads app.R.
# An unset value stays unset, so the application's default greeting still works.
Rscript -e 'saveRDS(Sys.getenv("GREETING_TEXT", unset = NA_character_), "/tmp/shiny-server/greeting.rds")'
# Bypass Rocker's /init script, which expects writable system log directories.
# R-session logs remain under /tmp/shiny-server; server diagnostics go to stderr.
exec /usr/bin/shiny-server /etc/shiny-server/shiny-server.conf \
    --pidfile /tmp/shiny-server.pid
