# syntax=docker/dockerfile:1.4
# Prod build: docker build --build-arg TAP_NAME=tap-travel-perk ...
# Dev build:  docker build --build-arg TAP_NAME=tap-travel-perk --build-arg LOADERS="target-bigquery target-bigquery-dev" ...
ARG TAP_NAME
ARG LOADERS="target-bigquery"

# Stage 1 → Builder: pre-build wheels for all meltano deps
FROM gcr.io/lumapps-registry/lumapps-python-build:3.10 AS builder
COPY requirements/meltano.txt .
RUN pip3 wheel --no-cache-dir --no-deps --wheel-dir /wheels -r meltano.txt

# Stage 2 → Runtime image
FROM gcr.io/lumapps-registry/lumapps-python:3.10
WORKDIR /app

# Install meltano from pre-built wheels
COPY --from=builder /wheels /wheels
# UV_VENV_SEED: meltano plugin venvs need pip/setuptools/wheel seeds (pkg_resources)
ENV UV_VENV_SEED=true
RUN apt-get update && \
    apt-get install -q -y --no-install-recommends python3-pip python3-wheel python3-pkg-resources && \
    pip3 install --no-cache --upgrade pip && \
    /usr/local/bin/pip3 install --no-cache /wheels/* && rm -rf /wheels && \
    apt-get purge -qy python3-pip python3-wheel && \
    apt-get clean && rm -rf /var/{cache,log}/apt/ /var/lib/apt/lists/

# Copy in-repo extractors first so meltano install can resolve local paths
COPY extractors/ /app/extractors/
COPY meltano/ /app/meltano/
WORKDIR /app/meltano

ARG TAP_NAME
ARG LOADERS
RUN meltano install extractor $TAP_NAME \
 && meltano install loader $LOADERS \
 && chown -R 1000:1000 /app/meltano \
 && mkdir -p /home/.local && chown -R 1000:1000 /home/.local

# Keep workdir at the meltano project so `meltano run` finds meltano.yml
# Do not run as root as you're not supposed to write anywhere inside the container
USER 1000

# Image information. Because it is dynamic, it must be placed at the end of the file
# for the Docker cache layers to be reused.
ARG GIT_VERSION
ARG GIT_SHA1
ARG BUILD_DATE
LABEL com.lumapps.image.authors=bi.developer@lumapps.com
LABEL com.lumapps.image.source=https://github.com/lumapps/business-bi/
LABEL com.lumapps.image.version=${GIT_VERSION}
LABEL com.lumapps.image.sha1=${GIT_SHA1}
LABEL com.lumapps.image.created=${BUILD_DATE}
