#!/usr/bin/env bash
# Builds PairUp from Code - OSS at the tag in UPSTREAM_TAG.
#   bash build.sh                 prepare, then compile and zip
#   bash build.sh --no-compile    prepare only (clone, patch, product.json, icons, extension)
#   bash build.sh --compile-only  compile and zip an already prepared ./vscode
# Env: UPSTREAM_TAG_OVERRIDE (use this tag, for drift.yml), PAIRUP_SRC (checkout of the
# private pairup-cloud repo, default ../pairup-cloud).
# The merge idea (overrides win, a key list dropped) and the npm retry loop follow VSCodium's
# prepare_vscode.sh (MIT, https://github.com/VSCodium/vscodium).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
MODE=all
case "${1:-}" in
  "") ;;
  --no-compile) MODE=prepare ;;
  --compile-only) MODE=compile ;;
  *) echo "usage: build.sh [--no-compile|--compile-only]" >&2; exit 2 ;;
esac
die() { echo "build.sh: $*" >&2; exit 1; }
warn() { echo "build.sh: warning: $*" >&2; }

TAG="${UPSTREAM_TAG_OVERRIDE:-$(tr -d '[:space:]' < UPSTREAM_TAG)}"
[ -n "$TAG" ] || die "no tag"
ARCH=x64

# Microsoft service keys to drop from product.json if present. Each is optional in
# IProductConfiguration, src/vs/base/common/product.ts at 1.144.0.
# Note: VSCodium does not delete keys. It overwrites the help URLs (prepare_vscode.sh
# lines 37-51) and rewrites *.data.microsoft.com hosts (undo_telemetry.sh lines 10-11).
# Code - OSS's own product.json has none of these except voiceWsUrl, so this list mostly
# guards against a newer tag adding them.
DELETE_KEYS='[
  "updateUrl","downloadUrl",
  "enableTelemetry","aiConfig","crashReporter","msftInternalDomains","showTelemetryOptOut",
  "removeTelemetryMachineId","enabledTelemetryLevels",
  "tasConfig","npsSurveyUrl","surveys",
  "tipsAndTricksUrl","introductoryVideosUrl","newsletterSignupUrl","youTubeUrl","requestFeatureUrl",
  "reportMarketplaceIssueUrl","emergencyAlertUrl","voiceWsUrl","settingsSearchUrl",
  "profileTemplatesUrl","configurationSync.store","editSessions.store",
  "chatParticipantRegistry","chatSessionRecommendations"
]'

winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

prepare() {
  command -v node >/dev/null || die "node is required"
  command -v git >/dev/null || die "git is required"

  # 1. clone (skip if present at the tag; then restore tracked files so patches re-apply)
  if [ -d vscode/.git ]; then
    have="$(git -C vscode describe --tags --exact-match HEAD 2>/dev/null || true)"
    [ "$have" = "$TAG" ] || die "vscode/ is at '$have', not $TAG. Delete vscode/ and run again."
    git -C vscode reset --hard -q "$TAG"
  else
    git -c core.autocrlf=false clone --depth 1 --branch "$TAG" https://github.com/microsoft/vscode.git vscode
  fi

  # 2. patches, in name order. patches/ may be empty (it is, at first).
  shopt -s nullglob
  for p in "$ROOT"/patches/*.patch; do
    echo "applying $(basename "$p")"
    git -C vscode apply --3way "$p"
  done
  shopt -u nullglob

  # 3. product.json: merge the overrides, delete the key list, two-space indent
  DELETE_KEYS="$DELETE_KEYS" node "$ROOT/tools/product.mjs" merge vscode/product.json "$ROOT/product.overrides.json"

  # 4. icons. At 1.144.0 resources/win32 has code.ico, code_70x70.png, code_150x150.png
  # (no 256 px png). Sized files from icons/ win over pairup-256.png.
  put() { if [ -f "$1" ]; then cp "$1" "$2"; else warn "$1 missing, kept upstream $2"; fi; }
  put icons/pairup.ico vscode/resources/win32/code.ico
  for s in 70 150; do
    if [ -f "icons/pairup-$s.png" ]; then cp "icons/pairup-$s.png" "vscode/resources/win32/code_${s}x${s}.png"
    else put icons/pairup-256.png "vscode/resources/win32/code_${s}x${s}.png"; fi
  done

  # 5. the extension from the private repo. An explicit PAIRUP_SRC must exist; the
  # default path may be missing (probe.yml), which only warns.
  src="${PAIRUP_SRC:-}"; explicit=1
  if [ -z "$src" ]; then src="$ROOT/../pairup-cloud"; explicit=0; fi
  src="${src//\\//}"
  if [ ! -d "$src/vscode" ]; then
    [ "$explicit" = 0 ] || die "PAIRUP_SRC=$src has no vscode/ folder"
    warn "no $src/vscode, skipping the extension"
  else
    node "$src/vscode/scripts/sync-web.mjs"   # fills media/ (app.js, app.css, favicon.svg)
    dst=vscode/extensions/pairup
    rm -rf "$dst"; mkdir -p "$dst"
    cp "$src/vscode/package.json" "$src/vscode/extension.js" "$dst/"
    cp -r "$src/vscode/media" "$dst/media"   # whole folder, so whatever sync-web adds comes along
    for f in package.json extension.js media/host.js media/pairup.svg media/app.js media/app.css media/favicon.svg; do
      [ -f "$dst/$f" ] || die "extension file missing: $f"
    done
  fi

  # 6. show the result
  node "$ROOT/tools/product.mjs" show vscode/product.json || die "product.json check failed"
}

make_zip() { # make_zip <folder> <zip path>
  local dir="$1" zip="$2"; rm -f "$zip"
  if command -v 7z >/dev/null 2>&1; then (cd "$dir" && 7z a -tzip -bso0 -bsp0 "$(winpath "$zip")" '*')
  elif command -v zip >/dev/null 2>&1; then (cd "$dir" && zip -qr "$zip" .)
  else powershell -NoProfile -Command "Compress-Archive -Path '$(winpath "$dir")\\*' -DestinationPath '$(winpath "$zip")' -Force"; fi
}

compile() {
  [ -d vscode ] || die "no vscode/, run without --compile-only first"
  export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"
  # Same env as Microsoft's product-build-win32-setup.yml lines 101-105 (public CI path)
  export ELECTRON_SKIP_BINARY_DOWNLOAD=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 FOUNDRY_LOCAL_SKIP_INSTALL=1
  export npm_config_arch="$ARCH" npm_config_foreground_scripts=true
  cd vscode
  for i in 1 2 3; do
    npm ci && break
    [ "$i" -lt 3 ] || die "npm ci failed 3 times"
    echo "npm ci failed ($i), retrying"; sleep $((15 * i))
  done
  # Microsoft's own pipeline (build/azure-pipelines/win32/steps/product-build-win32-compile.yml
  # lines 61 and 102) runs core-ci, then the -ci package task. The -ci task only packages:
  # it needs out-vscode-min and .build/extensions from core-ci. Task defined at
  # build/gulpfile.vscode.ts L619:
  #   const vscodeTaskCI = task.define(`vscode${dashed(platform)}${dashed(arch)}${dashed(minified)}-ci`, ...
  # The one-command alternative (L632 vscodeTask, also compiles Copilot from source) is
  # `vscode-win32-x64-min`; use it if core-ci + -ci fails.
  npm run gulp core-ci
  # The -ci packaging task expects the built-in Copilot extension already compiled (Microsoft's pipeline downloads it as a
  # VSIX); the non-CI chain compiles it from the tree first, so do the same. Found on the first runner build, 2026-11-03.
  npm run gulp compile-copilot-extension-build
  npm run gulp "vscode-win32-$ARCH-min-ci"
  cd ..

  # Output folder: gulpfile.vscode.ts L603 `VSCode${dashed(platform)}${dashed(arch)}`, placed
  # at path.dirname(root) (L138), the folder that holds vscode/.
  OUT_DIR="$ROOT/VSCode-win32-$ARCH"
  [ -d "$OUT_DIR" ] || die "gulp output $OUT_DIR not found"
  exe="$(node "$ROOT/tools/product.mjs" name vscode/product.json).exe"
  [ -f "$OUT_DIR/$exe" ] || die "$exe missing in $OUT_DIR"
  mkdir -p out
  zip="$ROOT/out/PairUp-win32-$ARCH-$TAG.zip"
  make_zip "$OUT_DIR" "$zip"
  (cd out && sha256sum "$(basename "$zip")" > SHA256SUMS && cat SHA256SUMS)
}

if [ "$MODE" != compile ]; then prepare; fi
if [ "$MODE" != prepare ]; then compile; fi
