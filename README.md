# release-actions

Shared GitHub Actions for publishing wakamex packages. Each package repository keeps a short `publish.yml` and `release-eligibility.yml` that call these, so a change to the release steps is made once here instead of in every repository.

Consumers reference the `v1` branch. Changes that keep the inputs and behavior compatible land on `main` and fast-forward `v1`. A breaking change goes to a new `v2` branch.

## Contents

| Path | Kind | What it does |
|---|---|---|
| `.github/workflows/python-validation.yml` | reusable workflow, job `validate` | Checks `uv.lock`, runs `python -m unittest discover -s tests`, and builds without local sources. |
| `pypi-publish` | composite action | Runs the `verify-release-tag` check against `uv --no-config version --short`, builds, and runs `uv publish --trusted-publishing always`. |
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
    uses: wakamex/release-actions/.github/workflows/python-validation.yml@v1
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
    uses: wakamex/release-actions/.github/workflows/python-validation.yml@v1

  publish:
    needs: validate
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v7.0.1
      - uses: wakamex/release-actions/pypi-publish@v1

  github-release:
    needs: publish
    permissions:
      contents: write
    uses: wakamex/release-actions/.github/workflows/github-release.yml@v1
```

## Binary releases

A multi-job validation workflow ends with a gate job. GitHub reports a skipped job as successful, so the gate runs with `if: always()` and checks every result:

```yaml
  validate:
    name: validate
    if: always()
    needs: [build, windows]
    runs-on: ubuntu-24.04
    steps:
      - uses: wakamex/release-actions/validate-gate@v1
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
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: wakamex/release-actions/verify-release-tag@v1
        with:
          version-command: cat VERSION
      - run: ./build-release-assets.sh release-assets
      - uses: actions/upload-artifact@v4
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
    uses: wakamex/release-actions/.github/workflows/binary-release.yml@v1
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
