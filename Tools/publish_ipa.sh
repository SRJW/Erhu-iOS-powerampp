#!/usr/bin/env bash
set -euo pipefail

ipa=${1:-dist/amp.ipa}
: "${GH_REPO:?Missing repository}"
: "${GH_TOKEN:?Missing workflow token}"
: "${IPA_BUILD_NUMBER:?Missing source build number}"
: "${IPA_SOURCE_SHA:?Missing source commit}"
[[ "$IPA_BUILD_NUMBER" =~ ^[0-9]+$ ]]
[[ "$IPA_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
test -s "$ipa"
tag="v0.1.0-amp.${IPA_BUILD_NUMBER}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

# A republish job uses the original build's version and SHA, not its own run number.
if gh api "repos/$GH_REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
  test "$(gh api "repos/$GH_REPO/commits/$tag" --jq '.sha')" = "$IPA_SOURCE_SHA"
else
  gh api --method POST "repos/$GH_REPO/git/refs" -f ref="refs/tags/$tag" -f sha="$IPA_SOURCE_SHA" >/dev/null
fi

# Drafts are included in the release list, even when lookup by tag returns 404.
release_id=$(gh api --paginate "repos/$GH_REPO/releases?per_page=100" \
  --jq ".[] | select(.tag_name == \"$tag\") | .id")
if [ -z "$release_id" ]; then
  python3 - "$temporary/release.json" <<'PY'
import json, os, sys
number = os.environ['IPA_BUILD_NUMBER']
source = os.environ['IPA_SOURCE_SHA']
body = ('Development IPA from successful iPhone build ' + number + '.\n\n'
        'Re-sign before installing, preserving the same authorized App Group for the app and widget. '
        'Signing requests do not grant provisioning permissions.\n\nSource: ' + source + '.')
if os.environ.get('NATIVE_CHECKS_RESULT') == 'success':
    body += '\nNative player interaction and rendered blend verification passed.'
else:
    body += '\nNative simulator checks were not selected for this publication; consult the original build for validation.'
with open(sys.argv[1], 'w') as output:
    json.dump(dict(tag_name='v0.1.0-amp.' + number, target_commitish=source,
                   name='amp — static artwork build ' + number, body=body,
                   draft=True, prerelease=True), output)
PY
  release_id=$(gh api --method POST "repos/$GH_REPO/releases" --input "$temporary/release.json" --jq '.id')
fi
[[ "$release_id" =~ ^[0-9]+$ ]]

gh api "repos/$GH_REPO/releases/$release_id/assets" > "$temporary/assets.json"
asset_id=$(python3 - "$temporary/assets.json" <<'PY'
import json, sys
assets = [a for a in json.load(open(sys.argv[1])) if a['name'] == 'amp.ipa']
assert len(assets) <= 1
if assets:
    assert assets[0]['state'] == 'uploaded', 'Existing upload is incomplete; inspect it before replacing it'
    print(assets[0]['id'])
PY
)
if [ -z "$asset_id" ]; then
  curl --fail-with-body --silent --show-error --request POST \
    --header "Authorization: Bearer $GH_TOKEN" \
    --header 'Content-Type: application/octet-stream' \
    --data-binary "@$ipa" \
    "https://uploads.github.com/repos/$GH_REPO/releases/$release_id/assets?name=amp.ipa" > "$temporary/asset.json"
else
  gh api "repos/$GH_REPO/releases/assets/$asset_id" > "$temporary/asset.json"
fi
python3 - "$ipa" "$temporary/asset.json" <<'PY'
import hashlib, json, pathlib, sys
ipa = pathlib.Path(sys.argv[1])
asset = json.load(open(sys.argv[2]))
assert asset['state'] == 'uploaded' and asset['size'] == ipa.stat().st_size
if asset.get('digest'):
    assert asset['digest'] == 'sha256:' + hashlib.sha256(ipa.read_bytes()).hexdigest()
PY
if [ "$(gh api "repos/$GH_REPO/releases/$release_id" --jq '.draft')" = 'true' ]; then
  gh api --method PATCH "repos/$GH_REPO/releases/$release_id" -F draft=false >/dev/null
fi
printf '[Download amp.ipa directly](https://github.com/%s/releases/download/%s/amp.ipa)\n' \
  "$GH_REPO" "$tag" >> "$GITHUB_STEP_SUMMARY"
