# pairup-editor

Scripts and patches that build PairUp from Code - OSS (the MIT-licensed core of VS Code) at one pinned upstream tag. The tag is in `UPSTREAM_TAG`.

PairUp is not made by or endorsed by Microsoft. The VS Code name and logo belong to Microsoft and are not used here. Extensions come from Open VSX. The build sends nothing to Microsoft and has no auto-update (no `updateUrl`). The product itself (server, page, extension) lives in a private repo and is copied in at build time.

## What is in here

- `build.sh`: clones upstream at the tag, applies `patches/*.patch`, merges `product.overrides.json` into `product.json`, copies icons and the PairUp extension, then compiles and zips.
- `.github/workflows/probe.yml`: checks the Windows runner (tools, Spectre libraries, disk, `npm ci` time). Run it first.
- `.github/workflows/build.yml`: the Windows build. Needs the secret `PAIRUP_CLOUD_DEPLOY_KEY`, a read-only deploy key on the private repo.
- `.github/workflows/drift.yml`: weekly, tries the patches on the newest upstream tag and opens an issue if they fail.

## Run it

Probe: Actions tab, Probe, Run workflow. Read the log for the `npm ci` time.

Build: Actions tab, Build, Run workflow (or push a tag `v*`). The zip and `SHA256SUMS` are an artifact for 7 days.

Locally (needs Git Bash, jq, Node from `vscode/.nvmrc`): `bash build.sh --no-compile` prepares `vscode/` only.

## Opening the zip

Windows may show a SmartScreen warning because the build is unsigned. Press More info, then Run anyway. Right-click the zip, Properties, Unblock before extracting. Compare the zip's SHA-256 with `SHA256SUMS`. Details: `docs/SMARTSCREEN.md`.

Code - OSS is MIT, Copyright Microsoft Corporation. This repo is MIT, see `LICENSE`.
