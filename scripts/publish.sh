#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != "--check" ) ]]; then
  print -u2 "Usage: ./scripts/publish.sh [--check]"
  exit 2
fi

repository="henrikhestnes/MacMouse"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
tag="v$version"
notes="releases/$tag.md"
asset="$PWD/dist.noindex/MacMouse.zip"

# These checks do not access GitHub, install anything, or launch the app.
python3 - "$version" "$notes" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import hashlib
import plistlib
import re
import subprocess
import sys

version, notes = sys.argv[1:]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected a stable semantic version in Resources/Info.plist.')
email = subprocess.check_output(['git', 'config', 'user.email'], text=True).strip()
if email != 'henrik.hestnes@hotmail.com':
    raise SystemExit('Set this repository\'s user.email to henrik.hestnes@hotmail.com before publishing.')
if subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip() != 'main':
    raise SystemExit('Publish from the main branch.')
allowed = {'Casks/macmouse.rb', 'README.md', 'scripts/publish.sh', 'scripts/publish-tap.sh', notes}
changed = set(subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], text=True).splitlines())
changed.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], text=True).splitlines())
if changed - allowed:
    raise SystemExit('Commit or set aside unrelated changes first: ' + ', '.join(sorted(changed - allowed)))
cask = Path('Casks/macmouse.rb').read_text()
assert re.search(r'^  version "' + re.escape(version) + r'"$', cask, re.M), 'Cask version does not match the app.'
asset = Path('dist.noindex/MacMouse.zip')
checksum = hashlib.sha256(asset.read_bytes()).hexdigest()
assert f'  sha256 "{checksum}"' in cask, 'Cask checksum does not match the release ZIP. Update it first.'
assert checksum in Path(notes).read_text(), 'Release notes checksum does not match the ZIP.'
bundle = Path('dist.noindex/MacMouse.app')
architectures = subprocess.check_output(['lipo', '-archs', str(bundle / 'Contents/MacOS/MacMouse')], text=True).split()
assert {'arm64', 'x86_64'} <= set(architectures), 'The release must support Apple Silicon and Intel.'
with ZipFile(asset) as archive:
    assert archive.testzip() is None, 'Damaged ZIP.'
    info = plistlib.loads(archive.read('MacMouse.app/Contents/Info.plist'))
    assert info['CFBundleShortVersionString'] == version, 'ZIP contains a different app version.'
    assert info['CFBundleIdentifier'] == 'io.macmouse.app'
    for name in ['Contents/Info.plist', 'Contents/MacOS/MacMouse', 'Contents/Resources/AppIcon.icns']:
        assert archive.read('MacMouse.app/' + name) == (bundle / name).read_bytes(), 'ZIP differs from the local bundle: ' + name
print(f'Validated MacMouse {version}, release notes, cask, ZIP, and commit email.')
PY
codesign --verify --deep --strict dist.noindex/MacMouse.app
# Every release must use the hardened runtime (./scripts/build.sh signs with --options runtime).
if [[ ! "$(codesign -d --verbose=1 dist.noindex/MacMouse.app 2>&1)" =~ 'flags=0x[0-9a-f]+\([^)]*runtime' ]]; then
  print -u2 'The app is not signed with the hardened runtime. Rebuild with ./scripts/build.sh --universal.'
  exit 1
fi
# Accessibility permission survives upgrades only while every release is signed with the same certificate.
if [[ "$(codesign -dr - dist.noindex/MacMouse.app 2>&1)" != *'identifier "io.macmouse.app" and certificate leaf = H"60e479dee9ef30d9ac25735c29c78e492c875bea"'* ]]; then
  print -u2 'Sign the release with the "MacSnip Release" certificate (./scripts/build.sh --universal).'
  exit 1
fi
ruby -c Casks/macmouse.rb

if [[ "${1:-}" == "--check" ]]; then
  print "Offline release checks passed. No GitHub changes made."
  exit 0
fi

# The user explicitly requested public GitHub hosting and a personal Homebrew tap.
account=$(gh api user --jq .login)
if [[ "${account:l}" != "henrikhestnes" ]]; then
  print -u2 "Sign gh in as henrikhestnes before publishing."
  exit 1
fi
# Create the repository privately on the first release; it becomes public once the release is verified.
if ! gh repo view "$repository" --json nameWithOwner >/dev/null 2>&1; then
  gh repo create "$repository" --private --description "Pointer speed, scroll wheel and mouse button settings for macOS"
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "https://github.com/$repository.git"
fi
if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
  git push --set-upstream origin main
fi
actual_repository=$(gh repo view "$repository" --json nameWithOwner --jq .nameWithOwner)
if [[ "${actual_repository:l}" != "${repository:l}" ]]; then
  print -u2 "Unexpected GitHub repository: $actual_repository"
  exit 1
fi
git fetch origin main --tags
git merge-base --is-ancestor origin/main HEAD
# Allow publication-only fixes when resuming, while keeping the app's tag fixed.
if git rev-parse --verify "$tag" >/dev/null 2>&1; then
  if ! git merge-base --is-ancestor "$tag^{commit}" HEAD || \
     ! git diff --quiet "$tag^{commit}" HEAD -- . \
       ':(exclude)Casks/macmouse.rb' ':(exclude)README.md' \
       ':(exclude)scripts/publish.sh' ':(exclude)scripts/publish-tap.sh' ":(exclude)$notes"; then
    print -u2 "$tag contains different app code. Use a new app version instead of moving the tag."
    exit 1
  fi
fi
git add Casks/macmouse.rb README.md scripts/publish.sh scripts/publish-tap.sh "$notes"
if ! git diff --cached --quiet; then
  git commit -m "Update Homebrew cask and release publishing for $tag"
fi
git push origin main
if ! git rev-parse --verify "$tag" >/dev/null 2>&1; then
  git tag -a "$tag" -m "MacMouse $version"
fi
git push origin "refs/tags/$tag"

release_state=$(gh release list --repo "$repository" --limit 100 --json tagName,isDraft \
  --jq ".[] | select(.tagName == \"$tag\") | if .isDraft then \"draft\" else \"published\" end")
if [[ -z "$release_state" ]]; then
  gh release create "$tag" "$asset" --repo "$repository" --verify-tag \
    --draft --title "MacMouse $version" --notes-file "$notes"
  release_state="draft"
elif [[ "$release_state" == "draft" ]]; then
  existing_asset=$(gh release view "$tag" --repo "$repository" --json assets \
    --jq '.assets[] | select(.name == "MacMouse.zip") | .name')
  if [[ -z "$existing_asset" ]]; then
    gh release upload "$tag" "$asset" --repo "$repository"
  fi
fi

# Download and verify the uploaded bytes before making anything public.
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/macmouse-release.XXXXXX")
gh release download "$tag" --repo "$repository" --pattern MacMouse.zip --dir "$verification_dir"
cmp "$asset" "$verification_dir/MacMouse.zip"

if [[ "$release_state" == "draft" ]]; then
  # Re-resolve the draft each time; a failed response may follow a successful edit.
  for attempt in 1 2 3 4; do
    if gh release edit "$tag" --repo "$repository" --draft=false --latest; then
      release_state="published"
      break
    fi
    if [[ "$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft)" == "false" ]]; then
      release_state="published"
      break
    fi
    if (( attempt < 4 )); then
      print -u2 "Publishing failed; retrying in 3 seconds ($attempt/4)."
      sleep 3
    fi
  done
  if [[ "$release_state" != "published" ]]; then
    print -u2 "GitHub could not publish $tag. The existing tag and ZIP have been preserved."
    print -u2 "Resolve the GitHub error above, then rerun ./scripts/publish.sh to resume."
    exit 1
  fi
fi
# Publish before changing visibility to avoid switching access during draft edits.
if [[ "$(gh repo view "$repository" --json isPrivate --jq .isPrivate)" == "true" ]]; then
  gh repo edit "$repository" --visibility public --accept-visibility-change-consequences
fi

# Check the public download without authentication and without installing it.
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --retry-all-errors \
  "https://github.com/$repository/releases/download/$tag/MacMouse.zip" \
  --output "$verification_dir/MacMouse-public.zip"
cmp "$asset" "$verification_dir/MacMouse-public.zip"
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --retry-all-errors \
  "https://raw.githubusercontent.com/$repository/main/Casks/macmouse.rb" \
  --output "$verification_dir/macmouse.rb"
cmp Casks/macmouse.rb "$verification_dir/macmouse.rb"
if [[ "$(gh repo view "$repository" --json isPrivate --jq .isPrivate)" != "false" ]]; then
  print -u2 "Repository is not public."
  exit 1
fi
./scripts/publish-tap.sh "$tag"
print "Published: https://github.com/$repository/releases/tag/$tag"
print "Install with:"
print "  brew install --cask henrikhestnes/tap/macmouse"
