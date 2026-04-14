FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev git openssh-client procps && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# ── Dependency layer ──────────────────────────────────────────────────────────
# Copy only manifests first so dep installs stay cached across source-only changes.

COPY hermes-agent/package.json hermes-agent/package-lock.json /opt/hermes/
COPY hermes-agent/scripts/whatsapp-bridge/package.json hermes-agent/scripts/whatsapp-bridge/package-lock.json /opt/hermes/scripts/whatsapp-bridge/

# Node deps and Playwright as root (--with-deps needs apt)
RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    cd /opt/hermes/scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force

# Python deps — resolved via uv.lock, project itself installed in the source layer below
COPY hermes-agent/pyproject.toml hermes-agent/uv.lock hermes-agent/README.md /opt/hermes/
RUN chown -R hermes:hermes /opt/hermes
USER hermes
RUN uv sync --frozen --all-extras --no-install-project

# ── Source layer ──────────────────────────────────────────────────────────────
USER root
COPY hermes-agent/ /opt/hermes
RUN chown -R hermes:hermes /opt/hermes
USER hermes
RUN uv sync --frozen --all-extras

USER root
RUN chmod +x /opt/hermes/docker/entrypoint.sh

ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
