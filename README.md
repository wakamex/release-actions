# release-actions

Shared GitHub Actions for publishing wakamex packages. Each package repository keeps a short `publish.yml` and `release-eligibility.yml` that call these, so a change to the release steps is made once here instead of in every repository.

Consumers reference the `v1` branch. Changes that keep the inputs and behavior compatible land on `main` and fast-forward `v1`. A breaking change goes to a new `v2` branch.

## Contents

| Path | Kind | What it does |
|---|---|---|
| `.github/workflows/python-validation.yml` | reusable workflow, job `validate` | Checks `uv.lock`, runs `python -m unittest discover -s tests`, and builds without local sources. |
| `pypi-publish` | composite action | Verifies the tag against the project version and the `release-notes/vX.Y.Z.md` file, builds, and runs `uv publish --trusted-publishing always`. |
| `.github/workflows/github-release.yml` | reusable workflow | Creates the GitHub Release for the tag from `release-notes/vX.Y.Z.md`, or leaves an existing Release unchanged. |

The PyPI step is a composite action, not a reusable workflow, because PyPI does not accept a reusable workflow as a trusted publisher. A composite action runs inside the caller's job, so PyPI sees the caller's `publish.yml` and `pypi` environment.

## Usage

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

## License

MIT
