# release-actions

Shared GitHub Actions for publishing wakamex packages. Each package repository keeps a short `publish.yml` and `release-eligibility.yml` that call these, so a change to the release steps is made once here instead of in every repository.

Consumers reference the `stable` branch, so a change here reaches every repository without editing it.

- Changes stay backward compatible: new inputs get defaults, and jobs, check names, and inputs are not renamed or removed while a caller uses them.
- Changes land on `main` first and are tested from `main` in a test repository. Promoting them fast-forwards `stable` and adds an annotated `vX.Y.Z` tag, so the tags list every commit `stable` has pointed to. A ruleset keeps `stable` fast-forward only.
- Each run records the commit it used: the job log shows `wakamex/release-actions/...@refs/heads/stable (SHA)` for workflows and the downloaded SHA for actions.
- Third-party actions are pinned to full commit SHAs and runners to versioned labels such as `ubuntu-24.04`. `.github/check-pins.sh` enforces both in this repository's lint job and can check a caller's `.github` directory.

## Contents

| Path | Kind | What it does |
|---|---|---|
| `.github/workflows/python-validation.yml` | reusable workflow, job `validate` | Checks `uv.lock`, runs `python -m unittest discover -s tests`, and builds without local sources. |
| `pypi-publish` | composite action | Runs the `verify-release-tag` check against `uv --no-config version --short`, builds, and runs `uv publish --trusted-publishing always --check-url https://pypi.org/simple/`, which skips files PyPI already has so a rerun completes a partial upload. Its optional `working-directory` input selects the package folder; release notes are still read from the repository root. |
| `.github/workflows/github-release.yml` | reusable workflow | Creates the GitHub Release for the tag from `release-notes/vX.Y.Z.md`, or leaves an existing Release unchanged. |
| `verify-release-tag` | composite action | Checks that the pushed tag is annotated, equals `v` plus the output of its `version-command` input, and has a nonempty, non-symlink `release-notes/vX.Y.Z.md`. |
| `validate-gate` | composite action | Fails unless every job in its `needs` input succeeded. Use it in the `validate` job of a multi-job validation workflow. |
| `.github/workflows/binary-release.yml` | reusable workflow | Takes the uploaded artifact named by its `artifact` input, writes `SHA256SUMS`, attests and verifies every asset, and creates the immutable GitHub Release from the notes, or verifies the existing one on a rerun. |

The PyPI step is a composite action, not a reusable workflow, because PyPI does not accept a reusable workflow as a trusted publisher. A composite action runs inside the caller's job, so PyPI sees the caller's `publish.yml` and `pypi` environment.

## Python packages

`.github/workflows/release-eligibility.yml`:

```yaml
name: Release eligibility

on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  release-eligible:
    uses: wakamex/release-actions/.github/workflows/python-validation.yml@stable
```

This produces the `release-eligible / validate` check that the `Validated release tags` ruleset requires.

`.github/workflows/publish.yml`:

```yaml
name: Publish to PyPI

on:
  push:
    tags: ["v*"]

permissions:
  contents: read

jobs:
  validate:
    uses: wakamex/release-actions/.github/workflows/python-validation.yml@stable

  publish:
    needs: validate
    runs-on: ubuntu-24.04
    environment: pypi
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: wakamex/release-actions/pypi-publish@stable

  github-release:
    needs: publish
    permissions:
      contents: write
    uses: wakamex/release-actions/.github/workflows/github-release.yml@stable
```

A repository that generates several packages from one source tree runs its generator after checkout and calls `pypi-publish` once per package, each with its `working-directory`. Each PyPI project trusts the same repository, `publish.yml`, and `pypi` environment.

## Binary releases

A multi-job validation workflow ends with a gate job. GitHub reports a skipped job as successful, so the gate runs with `if: always()` and checks every result:

```yaml
  validate:
    name: validate
    if: always()
    needs: [build, windows]
    runs-on: ubuntu-24.04
    steps:
      - uses: wakamex/release-actions/validate-gate@stable
        with:
          needs: ${{ toJSON(needs) }}
```

`publish.yml` keeps the repository's own build and hands the assets to the shared release job:

```yaml
jobs:
  validate:
    uses: ./.github/workflows/validation.yml

  build:
    needs: validate
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: wakamex/release-actions/verify-release-tag@stable
        with:
          version-command: cat VERSION
      - run: ./build-release-assets.sh release-assets
      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: release-assets
          path: release-assets/
          if-no-files-found: error

  release:
    needs: build
    permissions:
      artifact-metadata: write
      attestations: write
      contents: write
      id-token: write
    uses: wakamex/release-actions/.github/workflows/binary-release.yml@stable
    with:
      artifact: release-assets
```

Turn on immutable releases in the repository settings before the first release. The attestations are signed by the shared workflow, so verify a downloaded asset with:

```sh
gh attestation verify ASSET --repo OWNER/REPO \
  --signer-workflow wakamex/release-actions/.github/workflows/binary-release.yml
gh release verify-asset vX.Y.Z ASSET --repo OWNER/REPO
```

## License

MIT
