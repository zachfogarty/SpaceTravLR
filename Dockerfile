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

FROM nvidia/cuda:12.1.1-base-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 \
        python3.10-venv \
        python3-pip \
        build-essential \
        bedtools \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m pip install --no-cache-dir uv

WORKDIR /app
COPY . /app

# Mirrors the install steps in .github/workflows/python-package-conda.yml
RUN uv pip install --system --no-cache-dir -r requirements.txt \
    && uv pip install --system --no-cache-dir -e .

# SpaceShip.spawn_worker_gcp() mounts a GCS bucket at the output directory
# (self.outdir, resolved to an absolute path under /app) so that parallel
# tasks share the same gene queue lock files. launch.py and the rest of
# the project ship inside the image itself.
#
# No ENTRYPOINT/CMD here on purpose: spawn_worker_gcp() sets the Batch
# task's `commands` to `python3 launch.py`, which becomes the container's
# full command. Defining an ENTRYPOINT here as well would cause it to run
# twice.
