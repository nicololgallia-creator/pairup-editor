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
# guards against a newer tag adding them. PairUp ships no Copilot: compile() deletes the
# built-in chat extension after packaging and patches/05 turns AI features off by default.
# The chat keys stay (2026-11-03): without defaultChatAgent the 1.144 workbench never draws
# its window, and without builtInExtensionsEnabledWithAutoUpdates (overridden to []) the
# extension scan throws "is not iterable" and no extension loads.
DELETE_KEYS='[
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
  # Installer wizard images (icons/inno, from icons/tools/make-bmp.mjs); Microsoft's carry the VS Code logo.
  if [ -f icons/inno/inno-big-100.bmp ]; then cp icons/inno/inno-*.bmp vscode/resources/win32/
  else warn "icons/inno missing, the installer keeps the VS Code wizard images"; fi

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
    cp "$src/vscode/package.json" "$src/vscode/"*.js "$dst/"   # every top-level module: extension.js requires about.js and connect.js
    cp -r "$src/vscode/media" "$dst/media"   # whole folder, so whatever sync-web adds comes along
    for f in package.json extension.js about.js connect.js media/host.js media/pairup.svg media/app.js media/app.css media/favicon.svg; do
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
  # extensions/copilot/.esbuild.mts refuses to build once product.json has a quality unless this is set (attempt 9).
  export VSCODE_QUALITY="${VSCODE_QUALITY:-$(node -e "process.stdout.write(require('./vscode/product.json').quality || 'stable')")}"
  # The build id the app reports as its commit and the updater compares with the feed: one hash of this
  # repo's commit and the private repo's, so a change to either is a new version (build/lib/getVersion.ts).
  src="${PAIRUP_SRC:-$ROOT/../pairup-cloud}"; src="${src//\\//}"
  export BUILD_SOURCEVERSION="$(printf '%s %s' "$(git -C "$ROOT" rev-parse HEAD)" "$(git -C "$src" rev-parse HEAD 2>/dev/null || echo none)" | sha256sum | cut -c1-40)"
  echo "build id $BUILD_SOURCEVERSION"
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
  # The packaging step spawns a bare signtool.exe (build/gulpfile.vscode.ts, stripAuthenticodeSignature) to strip
  # Microsoft's signatures from the native binaries it re-stamps. The runner has it in the Windows SDK, off PATH.
  sdkbin="$(ls -d "/c/Program Files (x86)/Windows Kits/10/bin/10.0."*"/x64" 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$sdkbin" ]; then export PATH="$sdkbin:$PATH"; echo "signtool from $sdkbin"; else warn "no Windows SDK bin folder found; signtool.exe may be missing"; fi
  npm run gulp core-ci
  # The -ci packaging task expects the built-in Copilot extension already compiled (Microsoft's pipeline downloads it as a
  # VSIX); the non-CI chain compiles it from the tree first, so do the same. Found on the first runner build, 2026-11-03.
  npm run gulp compile-copilot-extension-build
  npm run gulp "vscode-win32-$ARCH-min-ci"
  # Output folder: gulpfile.vscode.ts L603 `VSCode${dashed(platform)}${dashed(arch)}`, placed
  # at path.dirname(root) (L138), the folder that holds vscode/.
  OUT_DIR="$ROOT/VSCode-win32-$ARCH"
  [ -d "$OUT_DIR/resources/app" ] || die "gulp output $OUT_DIR not found"
  # PairUp ships no Copilot. The packaging step needs the built-in chat extension present to finish, so it goes now.
  strip_copilot "$OUT_DIR"
  # The installer (build/gulpfile.vscode.win32.ts): inno_updater into tools/, then Inno Setup on build/win32/code.iss.
  npm run gulp "vscode-win32-$ARCH-inno-updater"
  npm run gulp "vscode-win32-$ARCH-user-setup"
  cd ..

  exe="$(node "$ROOT/tools/product.mjs" name vscode/product.json).exe"
  [ -f "$OUT_DIR/$exe" ] || die "$exe missing in $OUT_DIR"
  mkdir -p out
  zip="$ROOT/out/PairUp-win32-$ARCH-$TAG.zip"
  make_zip "$OUT_DIR" "$zip"
  setup="$(ls vscode/.build/win32-$ARCH/user-setup/*Setup*.exe 2>/dev/null | head -1 || true)"
  [ -n "$setup" ] || die "installer not found under vscode/.build/win32-$ARCH/user-setup"
  mv "$setup" "$ROOT/out/PairUpSetup-$ARCH-$TAG.exe"
  (cd out && sha256sum *.zip *.exe > SHA256SUMS && cat SHA256SUMS)
  node "$ROOT/tools/update-feed.mjs" "$OUT_DIR/resources/app/product.json" "$ROOT/out" "$TAG"
}

strip_copilot() { # strip_copilot <packaged app folder>: only ever the two Copilot folders inside a real build output
  local app="$1"
  [ -n "$app" ] && [ -f "$app/resources/app/product.json" ] || die "strip_copilot: $app is not a packaged app"
  for d in "resources/app/extensions/copilot" "bin/copilot-shim"; do
    [ -e "$app/$d" ] && rm -r -- "$app/$d" && echo "removed $d"
  done
  return 0
}

if [ "$MODE" != compile ]; then prepare; fi
if [ "$MODE" != prepare ]; then compile; fi
