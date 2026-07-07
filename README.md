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


## Training the model

Load the example [Slide-tags]((https://www.nature.com/articles/s41586-023-06837-4)) Human Tonsil data.

```python
adata = sc.read_h5ad('data/snrna_germinal_center.h5ad')
```

Create a SpaceShip and run the preprocessing pipeline (CellOracle GRN inference, COMMOT cell-cell communication, and NicheNet ligand-target links). This happens once per dataset and populates `outdir` (default `./output`) with everything training needs:

```python
from SpaceTravLR.spaceship import SpaceShip

spacetravlr = SpaceShip(name='myTonsil').setup_(adata)

assert spacetravlr.is_everything_ok()
```

Training itself runs out-of-process, driven by a `launch.py` script that any number of workers can run in parallel (see `tutorial/launch.py`):

```python
# launch.py
from SpaceTravLR.spaceship import SpaceShip

spacetravlr = SpaceShip(name='myTonsil', outdir='output/')
assert spacetravlr.is_everything_ok()
spacetravlr.fit()
```

`fit()` (an alias for `run_spacetravlr()`) trains one spatial CNN per gene. Genes are pulled off a shared queue backed by lock files in `outdir/betadata/`, so every worker pointed at the same `outdir` — whether that's one `launch.py` process on your laptop or many spawned across a cluster — trains a disjoint set of genes without duplicating work. Each finished gene is written to `output/betadata/<GENE>_betadata.parquet`, and the first worker to start also writes `output/betadata/run_params.json` recording the hyperparameters below:

| parameter | default | meaning |
|---|---|---|
| `max_epochs` | 150 | training epochs per gene |
| `learning_rate` | 5e-3 | optimizer learning rate |
| `spatial_dim` | 64 | resolution of the rasterized spatial map fed to the CNN |
| `batch_size` | 512 | training batch size |
| `radius` | 300 | spatial radius (in `adata.obsm['spatial']` units) for secreted ligand signaling |
| `contact_distance` | 50 | distance for contact-dependent (juxtacrine) signaling |

Pass any of these as kwargs to `.fit(...)` in `launch.py` (e.g. `spacetravlr.fit(max_epochs=100, radius=250)`) before spawning workers, since the first worker to start bakes them into `run_params.json` for that `outdir` and every later worker reuses them.

For a small dataset you can just call `spacetravlr.fit()` directly in-process instead of spawning workers. For anything bigger, spawn one or more parallel workers, each running `launch.py` against the same `outdir`:

- **On a SLURM cluster:**
  ```python
  spacetravlr.spawn_worker(
      python_path='.venv/bin/python',
      partition='preempt'
  )
  ```
  Call `spawn_worker` again (any number of times) to add more parallel workers — they all pull from the same gene queue.

- **On Google Cloud Batch** — see [Running on Google Cloud Batch](#running-on-google-cloud-batch) below; pass `task_count` to run several parallel tasks within one job.

Training for a dataset is complete once every gene in `adata.var_names` has a `output/betadata/<GENE>_betadata.parquet` file.

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


## Perturbing gene expression (in silico)

Once training has produced `output/betadata/*_betadata.parquet` files, load the trained model to run perturbations. This is typically a separate session from training (e.g. a local notebook, after workers finished on a cluster) — point a `SpaceShip` at the same `outdir` and load the *processed* AnnData that training used (`output/input_data/_adata.h5ad`), not the original raw input:

```python
from SpaceTravLR.spaceship import SpaceShip

spacetravlr = SpaceShip(name='myTonsil', outdir='output')  # same outdir used for training
adata = sc.read_h5ad('output/input_data/_adata.h5ad')

spacetravlr.setup_perturbations(
    adata=adata,
    use_float16=True,   # halves memory use when loading betas
    # subsample=5000,   # optional: only load betas for a random subset of cells
)
```

Pick which cells to perturb. Pass explicit cell names/indices, or select a region interactively on the spatial (or UMAP) layout:

```python
scatter = spacetravlr.interactive_select(adata, annot='cell_type_2', mode='spatial')
scatter.show()
# ... draw a selection in the widget, then:
cells = scatter.selection()
```

Then simulate the perturbation — e.g. knocking out `FOXO1` in just the selected cells:

```python
simulated = spacetravlr.perturb(
    target='FOXO1',
    gene_expr=0,      # 0 = knockout; any positive value forces that expression level instead
    propagation=4,    # number of spatial signal-propagation steps
    cells=cells,       # omit (or pass None) to perturb every cell instead of a subset
)
```

`perturb` returns a `cells x genes` DataFrame of *simulated* expression for **every** cell in `adata`, not just the ones you perturbed. At each of the `propagation` steps, every cell's received ligand signal is recomputed from its neighbors' current (simulated) expression — secreted signaling within `radius` and contact-dependent signaling within `contact_distance`, using whichever values were set during training for this model — so the predicted effect spreads outward from the perturbed cells to nearby cells over successive hops. To see that effect, diff the result against the unperturbed expression:

```python
baseline = adata.to_df(layer='imputed_count')
delta = simulated - baseline

delta.loc[cells]                                            # direct effect on the perturbed cells
delta.drop(index=cells).abs().sum(axis=1).sort_values(ascending=False)  # biggest knock-on effects on nearby, non-perturbed cells
```

Increasing `propagation` lets the effect travel further (more hops) through the spatial neighborhood before the simulation stops. You can perturb multiple genes in one call by passing equal-length lists for `target` and `gene_expr`, e.g. `target=['FOXO1', 'PAX5'], gene_expr=[0, 0]`.


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
