# syntax=docker/dockerfile:1.4
# Stage 1 → Builder image
FROM gcr.io/lumapps-registry/lumapps-python-build:3.13 AS builder

COPY requirements/dbt.txt .
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN --mount=type=cache,id=cache-pip,target=/root/.cache/pip <<EOF
set -e
python3 -m venv $VIRTUAL_ENV
python3 -m pip install -U pip setuptools
python3 -m pip install --no-deps -r dbt.txt
EOF

# Stage 2 → Runtime image
FROM gcr.io/lumapps-registry/lumapps-python:3.13

WORKDIR /app

ENV DBT_LOG_PATH=/app/logs
ENV DBT_TARGET_PATH=/app/target

ENV VIRTUAL_ENV=/opt/venv
COPY --from=builder $VIRTUAL_ENV $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

COPY dbt/ /app/dbt/
WORKDIR /app/dbt
RUN dbt deps --profiles-dir /app/dbt

WORKDIR /app

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
