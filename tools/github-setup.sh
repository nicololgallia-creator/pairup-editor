#!/usr/bin/env bash
# One-time GitHub setup for the PairUp editor build, run by the repository owner from this folder in Git Bash:
#   bash tools/github-setup.sh
# It makes a read-only deploy key for the private product repo, creates this public repo and pushes it, stores the key
# as the build's secret, and starts the probe workflow. Needs `gh auth login` done once. Nothing here is a secret.
set -euo pipefail
PRIVATE="nicololgallia-creator/pairup-cloud"
PUBLIC="nicololgallia-creator/pairup-editor"
KEY="${TMPDIR:-/tmp}/pairup_editor_deploy"

echo "1. deploy key (read-only) on $PRIVATE"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "pairup-editor build, read-only deploy key" -f "$KEY"
gh api -X POST "repos/$PRIVATE/keys" -f title="pairup-editor build (read-only)" -f key="$(cat "$KEY.pub")" -F read_only=true --jq '"   added key id \(.id)"'

echo "2. public repo $PUBLIC, pushed from this folder"
if gh repo view "$PUBLIC" >/dev/null 2>&1; then
  echo "   exists already"
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$PUBLIC.git"
  git push -u origin main
else
  gh repo create "$PUBLIC" --public --source . --remote origin --push \
    --description "Builds PairUp, a code editor, from Code - OSS. Scripts, patches, and workflows only; not made by or endorsed by Microsoft."
fi

echo "3. the key as the build's secret"
gh secret set PAIRUP_CLOUD_DEPLOY_KEY --repo "$PUBLIC" < "$KEY"
rm -f "$KEY" "$KEY.pub"

echo "4. the probe workflow (about 10 minutes)"
gh workflow run probe.yml --repo "$PUBLIC"
sleep 5
gh run list --repo "$PUBLIC" --workflow probe.yml --limit 1
echo "done. Watch it with: gh run watch --repo $PUBLIC"
