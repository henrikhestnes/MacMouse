#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if (( $# > 1 )); then
  print -u2 'Usage: ./scripts/publish-tap.sh [vVERSION]'
  exit 2
fi
app_repository="henrikhestnes/MacMouse"
tap_repository="henrikhestnes/homebrew-tap"
if [[ "$(git config user.email)" != "henrik.hestnes@hotmail.com" ]]; then
  print -u2 'Set this repository’s user.email to henrik.hestnes@hotmail.com first.'
  exit 1
fi
account=$(gh api user --jq .login)
if [[ "${account:l}" != "henrikhestnes" ]]; then
  print -u2 'Sign gh in as henrikhestnes before publishing the tap.'
  exit 1
fi
if (( $# == 1 )); then
  tag="$1"
else
  tag=$(gh release view --repo "$app_repository" --json tagName --jq .tagName)
fi
if [[ ! "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Expected a stable release tag, got: $tag"
  exit 1
fi
if [[ "$(gh release view "$tag" --repo "$app_repository" --json isDraft --jq .isDraft)" != "false" ]]; then
  print -u2 'Publish the app release before updating the tap.'
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/macmouse-tap.XXXXXX")
mkdir -p "$work/asset"
# Read the cask from the release tag, never from an unpublished working tree.
gh api "repos/$app_repository/contents/Casks/macmouse.rb?ref=$tag" --jq .content \
  | /usr/bin/base64 --decode > "$work/macmouse.rb"
gh release download "$tag" --repo "$app_repository" --pattern MacMouse.zip --dir "$work/asset"
python3 - "$work" "$tag" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import re
import sys
from zipfile import ZipFile
work, tag = Path(sys.argv[1]), sys.argv[2]
cask = (work / 'macmouse.rb').read_text()
checksum = hashlib.sha256((work / 'asset/MacMouse.zip').read_bytes()).hexdigest()
assert re.search(r'^cask "macmouse" do$', cask, re.M), 'Unexpected cask token.'
assert f'  version "{tag[1:]}"' in cask, 'Cask version differs from the published release.'
assert f'  sha256 "{checksum}"' in cask, 'Published ZIP does not match the cask checksum.'
with ZipFile(work / 'asset/MacMouse.zip') as archive:
    assert archive.testzip() is None, 'Damaged published ZIP.'
    info = plistlib.loads(archive.read('MacMouse.app/Contents/Info.plist'))
    assert info['CFBundleShortVersionString'] == tag[1:], 'Published ZIP contains a different app version.'
    assert info['CFBundleIdentifier'] == 'io.macmouse.app', 'Unexpected app in the published ZIP.'
assert '  url "https://github.com/henrikhestnes/MacMouse/releases/download/v#{version}/MacMouse.zip"' in cask, 'Unexpected download URL.'
print(f'Verified the published MacMouse {tag} ZIP and cask.')
PY
ruby -c "$work/macmouse.rb"

existing=false
if gh repo view "$tap_repository" --json nameWithOwner,isPrivate > "$work/repository.json" 2> "$work/repository.error"; then
  python3 - "$work/repository.json" <<'PY'
import json
import sys
repo = json.load(open(sys.argv[1]))
assert repo['nameWithOwner'].lower() == 'henrikhestnes/homebrew-tap', 'Unexpected repository.'
assert repo['isPrivate'] is False, 'The existing homebrew-tap repository is private. It was left unchanged.'
PY
  existing=true
  gh repo clone "$tap_repository" "$work/repo"
else
  if ! /usr/bin/grep -Eq 'Could not resolve to a Repository|HTTP 404|Not Found' "$work/repository.error"; then
    cat "$work/repository.error" >&2
    exit 1
  fi
  git init --quiet --initial-branch=main "$work/repo"
fi

git -C "$work/repo" config user.name "$(git config user.name)"
git -C "$work/repo" config user.email henrik.hestnes@hotmail.com
mkdir -p "$work/repo/Casks"
cp "$work/macmouse.rb" "$work/repo/Casks/macmouse.rb"
# The tap is shared with the other apps. Add a MacMouse row to its README without touching the others.
if [[ -e "$work/repo/README.md" ]] && ! /usr/bin/grep -q 'henrikhestnes/tap/macmouse' "$work/repo/README.md"; then
  row='| [MacMouse](https://github.com/henrikhestnes/MacMouse), pointer speed, scroll wheel and mouse button settings for mice | `brew install --cask henrikhestnes/tap/macmouse` |'
  # Keep the table alphabetical: insert before the first app that sorts after MacMouse, or after the last row.
  awk -v row="$row" '
    /^\| \[/ { if (!done && $0 > row) { print row; done = 1 } }
    { print }
    END { if (!done) exit 3 }
  ' "$work/repo/README.md" > "$work/README.new" || {
    awk -v row="$row" -v last="$(/usr/bin/grep -n '^| \[' "$work/repo/README.md" | tail -1 | cut -d: -f1)" \
      '{ print } NR == last { print row }' "$work/repo/README.md" > "$work/README.new"
  }
  mv "$work/README.new" "$work/repo/README.md"
  git -C "$work/repo" add README.md
fi
git -C "$work/repo" add Casks/macmouse.rb
if ! git -C "$work/repo" diff --cached --quiet; then
  git -C "$work/repo" commit -m "Update MacMouse cask to $tag"
fi
if [[ "$existing" == "true" ]]; then
  git -C "$work/repo" push origin HEAD
else
  gh repo create "$tap_repository" --public \
    --description "Homebrew casks for Henrik Hestnes’s apps" \
    --source "$work/repo" --remote origin --push
fi
branch=$(git -C "$work/repo" branch --show-current)
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --retry-all-errors \
  "https://raw.githubusercontent.com/$tap_repository/$branch/Casks/macmouse.rb" \
  --output "$work/public-cask.rb"
cmp "$work/macmouse.rb" "$work/public-cask.rb"
print "Tap published: https://github.com/$tap_repository"
print 'Install with: brew install --cask henrikhestnes/tap/macmouse'
