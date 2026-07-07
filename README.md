[![Tests](https://github.com/Koushul/SpaceOracle/actions/workflows/python-package-conda.yml/badge.svg?branch=main)](https://github.com/Koushul/SpaceOracle/actions/workflows/python-package-conda.yml)

# Why SpaceTravLR 🌔️ ?

**SpaceTravLR** (**S**patially perturbing **T**ranscription factors, **L**igands & **R**eceptors)


<p align="center">
  <img src="./assets/overview.svg" alt="overview" style="width:1200px"/>
</p>

SpaceTravLR leverages convolutional neural networks to generate a sparse graph with differentiable edges. This enables signals to propagate both within cells through regulatory edges and between cells through ligand–mediated connections.

<p align="center">
  <img src="./assets/model.svg" alt="overview" style="width:1200px"/>
</p>


## Core Features
- predicting niche-specific perturbation outcome at single cell resolution
- inferring functional cell-cell communications events
- identifying spatial domains and functional microniches and their driver genes


##  Quick start

Make & sync your Environment the [modern](https://docs.astral.sh/uv/) way

~~pip install -r requirements.txt~~

```bash
uv pip install SpaceTravLR==0.1.17
```


## Installing from Source
```bash
uv venv
source .venv/bin/activate
uv sync
```


Load the example [Slide-tags]((https://www.nature.com/articles/s41586-023-06837-4)) Human Tonsil data.

```python
adata = sc.read_h5ad('data/snrna_germinal_center.h5ad')
```

Create a SpaceShip
```python
from SpaceTravLR.spaceship import SpaceShip

spacetravlr = SpaceShip(name='myTonsil').setup_(adata)

assert spacetravlr.is_everything_ok()

spacetravlr.spawn_worker(
    python_path='.venv/bin/python',
    partition='preempt'
)
```

SpaceTravLR generates a queue of genes that each worker consumes in parallel. spacetravlr.spawn_worker submits a new job to the clusters.

### Running on Google Cloud Batch

`spawn_worker` submits to a SLURM cluster. If you don't have one, `spawn_worker_gcp` submits the same `launch.py` run as a [Google Cloud Batch](https://cloud.google.com/batch) job instead:

```python
spacetravlr.spawn_worker_gcp(
    project_id='my-gcp-project',
    region='us-central1',
    image_uri='us-central1-docker.pkg.dev/my-gcp-project/spacetravlr/spacetravlr:latest',
    gcs_bucket='my-bucket/myTonsil',  # mounted at spacetravlr.outdir in every task
    task_count=4,                    # parallel workers pulling from the gene queue
)
```

This requires two things beyond `pip install google-cloud-batch` (included in `requirements.txt`):

1. **A container image.** Build it from the repo's `Dockerfile`, from a build context that also includes your own `launch.py` (see `tutorial/launch.py`), then push it somewhere your project can pull from:
   ```bash
   docker build -t us-central1-docker.pkg.dev/my-gcp-project/spacetravlr/spacetravlr:latest .
   docker push us-central1-docker.pkg.dev/my-gcp-project/spacetravlr/spacetravlr:latest
   ```
2. **A GCS bucket for `gcs_bucket`.** Batch mounts it at `spacetravlr.outdir` inside every task via Cloud Storage FUSE, so parallel workers coordinate through the same gene-queue lock files the same way SLURM workers do over a shared cluster filesystem.

Pass `accelerator_type=None` to run CPU-only, or set `machine_type`/`accelerator_type`/`accelerator_count` to size the GPU worker VMs.


##  Outputs
<pre>
output/
├── input_data/
│   ├── _adata.h5ad
│   ├── celloracle_links.pkl
│   ├── communication.pkl
│   ├── LRs.parquet
├── betadata/
│   ├── PAX5_betadata.parquet
│   ├── FOXO1_betadata.parquet
│   ├── CD79A_betadata.parquet
│   ├── ...
│   ├── IL21_betadata.parquet
│   ├── IL4_betadata.parquet
│   ├── CCR4_betadata.parquet
├── logs/
│   ├── training_TIMESTAMP.log

</pre>

##  Results

<p align="center">
  <img src="./assets/GC_FOXO1_KO.svg" alt="overview" style="width:1200px"/>
</p>



## Citation

If you find SpaceTravLR useful in your research or projects, please cite our paper:
```
