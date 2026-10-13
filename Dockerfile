# Keep the R version explicit. This tag can still receive maintenance updates.
FROM rocker/shiny:4.6.1 AS runtime

USER root
WORKDIR /srv/shiny-server
# Install/check dependencies before app code, preserving the cached package layer.
COPY requirements.R /opt/demo/requirements.R
RUN Rscript /opt/demo/requirements.R \
    && rm -rf /srv/shiny-server/*

COPY app.R /srv/shiny-server/app.R
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf
COPY scripts/start.sh /opt/demo/start.sh
COPY scripts/probe.R /opt/demo/probe.R
COPY scripts/restore-environment.R /home/shiny/.Rprofile
ENV HOME=/tmp TMPDIR=/tmp SHINY_LOG_STDERR=1
# Server and R sessions share this unprivileged user, including during health probes.
USER shiny
EXPOSE 3838
HEALTHCHECK --interval=10s --timeout=15s --start-period=30s --retries=3 \
    CMD Rscript /opt/demo/probe.R http://127.0.0.1:3838/
CMD ["bash", "/opt/demo/start.sh"]

# Optional local tests: test dependencies and repository scripts stay out of runtime.
FROM runtime AS tests
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/* \
    && install2.r --error --skipinstalled testthat
COPY scripts/ /srv/shiny-server/scripts/
COPY tests/ /srv/shiny-server/tests/
COPY requirements.R /srv/shiny-server/requirements.R
USER shiny
CMD ["bash", "scripts/test.sh"]

# The default image is the runtime, not the preceding test environment.
FROM runtime AS application
