# Confirmed Shiny demo fixes

These notes describe issues reproduced during local container testing. They do
not establish that this repository has already been deployed on the hosting host.

## R workers did not receive GREETING_TEXT

The container had the requested environment variable, but the web page showed
the default greeting. Shiny Server constructs a reduced environment for R
workers. Passing a variable to Docker alone was therefore insufficient.

`scripts/start.sh` saves only the public greeting as RDS data in
`/tmp/shiny-server/greeting.rds`, with private file permissions.
`scripts/restore-environment.R` is copied to `/home/shiny/.Rprofile`; R loads it
at worker startup and restores the value for `Sys.getenv` in `app.R`.
An unset variable retains the app's fallback. No complete CI environment or
credentials are exported. Quotes and dollar signs were verified through the
actual Compose file and the rendered page.

Prevention: retain both startup files and the Dockerfile's profile copy.
The build smoke test explicitly checks its chosen greeting, in addition to the
health check. Recreate the container after changing the runtime value.

## Read-only runtime failed to create bookmark storage

The HTTP request failed because Shiny Server tried to create bookmark storage
under `/var/lib/shiny-server`, even though this app does not enable bookmarking.

`shiny-server.conf` sets `bookmark_state_dir` and session logs under
`/tmp/shiny-server`. `scripts/start.sh` creates the initial directory.
The PID file also lives in `/tmp`, and the container starts Shiny Server
directly rather than Rocker's default initialization script. Application
diagnostics are forwarded to container logs with `SHINY_LOG_STDERR=1`.

Prevention: retain these paths when using a non-root user and read-only root.
The Compose smoke test verified HTTP access and reactive browser interaction
with the production `noexec` tmpfs settings. Runtime logs and bookmark paths
are disposable; persistent storage needs a separately reviewed configuration.

## Script tests could not execute their fake Git program

The tests create a fake Git executable in a temporary directory. A `noexec`
mount there prevented it from running, producing a permission error.

Use the README's separate test image with an explicitly executable tmpfs:
`--tmpfs /tmp:rw,exec,nosuid,size=256m`. Omitting `noexec` alone did not remove
Docker's default mount restriction in the tested environment.
Run as the image's non-root user so the permission checks exercise real denial.

Prevention: keep this exception limited to the disposable test container.
Both app Compose files and build/deploy probes continue to use `noexec`.
