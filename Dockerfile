# Container image for running SpaceTravLR training jobs on Google Cloud Batch
# (the Google Batch equivalent of the SLURM `spawn_worker` path).
#
# Build context must be a project directory that contains your own
# `launch.py` (see tutorial/launch.py for an example) alongside this
# repository, since SpaceShip.spawn_worker_gcp() runs `python3 launch.py`
# from the image's working directory, just like spawn_worker() does over
# SLURM.
#
# Build & push:
#   docker build -t REGION-docker.pkg.dev/PROJECT_ID/REPO/spacetravlr:latest .
#   docker push REGION-docker.pkg.dev/PROJECT_ID/REPO/spacetravlr:latest
#
# Then pass that image URI to SpaceShip.spawn_worker_gcp(image_uri=...).

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM nvidia/cuda:12.6.3-base-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Ubuntu 24.04 ships Python 3.12 as python3, which satisfies anndata==0.12.10's
# Python>=3.11 requirement (requirements.txt). Ubuntu 22.04's default Python
# 3.10 does not, hence the newer base image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        build-essential \
        bedtools \
        git \
    && rm -rf /var/lib/apt/lists/*

# uv comes from Astral's own image (their documented Docker install path,
# see https://docs.astral.sh/uv/guides/integration/docker/) rather than
# `curl astral.sh/uv/install.sh | sh` or `pip install uv`: the former can
# fail TLS verification depending on the build host's CA trust/proxy setup,
# and the latter hits Ubuntu 24.04's PEP 668 "externally managed
# environment" guard on system pip.
COPY --from=uv /uv /uvx /usr/local/bin/

# Install into a real venv rather than the system Python: Ubuntu 24.04 marks
# /usr's Python as PEP 668 "externally managed", and uv enforces that marker
# the same way pip does (passing --system alone does not opt back in). A
# venv is exempt, and putting it first on PATH means `python3 launch.py`
# (however it's later invoked -- spawn_worker_gcp, an interactive shell,
# etc.) picks it up automatically, no activation step needed.
RUN python3 -m venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

WORKDIR /app
COPY . /app

# Mirrors the install steps in .github/workflows/python-package-conda.yml
RUN uv pip install --no-cache-dir -r requirements.txt \
    && uv pip install --no-cache-dir -e .

# SpaceShip.spawn_worker_gcp() mounts a GCS bucket at the output directory
# (self.outdir, resolved to an absolute path under /app) so that parallel
# tasks share the same gene queue lock files. launch.py and the rest of
# the project ship inside the image itself.
#
# No ENTRYPOINT/CMD here on purpose: spawn_worker_gcp() sets the Batch
# task's `commands` to `python3 launch.py`, which becomes the container's
# full command. Defining an ENTRYPOINT here as well would cause it to run
# twice.
