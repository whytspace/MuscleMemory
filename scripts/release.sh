#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh patch|minor|major

Creates a local release commit and annotated tag.

  patch    bump X.Y.Z to X.Y.(Z+1)
  minor    bump X.Y.Z to X.(Y+1).0
  major    bump X.Y.Z to (X+1).0.0

The script does not push. Publish with:
  git push origin main
  git push origin vX.Y.Z
EOF
}

die() {
  echo "release: $*" >&2
  exit 1
}

release_type="${1:-}"
case "$release_type" in
  patch | minor | major) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

toc="MuscleMemory.toc"
changelog="CHANGELOG.md"

[ -f "$toc" ] || die "missing $toc"
[ -f "$changelog" ] || die "missing $changelog"

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || die "releases must be cut from main, not $branch"

status="$(git status --porcelain)"
[ -z "$status" ] || die "worktree must be clean before cutting a release"

current_version="$(awk -F': *' '/^## Version:/ { print $2; exit }' "$toc")"
[[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "expected semantic ## Version in $toc, got '$current_version'"

IFS=. read -r major minor patch <<<"$current_version"
case "$release_type" in
  patch)
    patch=$((patch + 1))
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
esac

version="$major.$minor.$patch"
tag="v$version"
today="$(date +%Y-%m-%d)"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi

# Warn (don't block) when the Unreleased section has no notes: such a release
# ships only a maintenance placeholder to CurseForge. Done before any file is
# mutated so aborting leaves the worktree untouched.
unreleased="$(awk '
  /^## Unreleased[[:space:]]*$/ { grab = 1; next }
  grab && /^## / { exit }
  grab { print }
' "$changelog")"
if [ -z "$(printf '%s' "$unreleased" | tr -d '[:space:]')" ]; then
  echo "release: warning — '## Unreleased' has no notes; $tag will ship as a maintenance release." >&2
  printf 'release: continue anyway? [y/N] ' >&2
  read -r reply
  case "$reply" in
    y | Y | yes | YES) ;;
    *) die "aborted; add notes under '## Unreleased' first" ;;
  esac
fi

devc luacheck .
devc busted
devc stylua --check .
# Not --strict: shipping a partly translated locale is fine (it falls back to
# English), but a dead entry or a broken format marker is not.
devc lua scripts/check-locales.lua --release

toc_tmp="$(mktemp "$toc.XXXXXX")"
if ! awk -v version="$version" '
  BEGIN { updated = 0 }
  /^## Version:/ && updated == 0 {
    print "## Version: " version
    updated = 1
    next
  }
  { print }
  END { if (updated == 0) exit 1 }
' "$toc" >"$toc_tmp"; then
  rm -f "$toc_tmp"
  die "could not update $toc"
fi
mv "$toc_tmp" "$toc"

changelog_tmp="$(mktemp "$changelog.XXXXXX")"
if ! awk -v version="$version" -v today="$today" '
  BEGIN { updated = 0 }
  /^## Unreleased[[:space:]]*$/ && updated == 0 {
    print
    print ""
    print "## " version " - " today
    updated = 1
    next
  }
  { print }
  END { if (updated == 0) exit 1 }
' "$changelog" >"$changelog_tmp"; then
  rm -f "$changelog_tmp"
  die "could not find '## Unreleased' in $changelog"
fi
mv "$changelog_tmp" "$changelog"

git add "$toc" "$changelog"
if git diff --cached --quiet; then
  die "release produced no version or changelog changes"
fi

git commit -m "chore: release $tag"
git tag -a "$tag" -m "$tag"

cat <<EOF
Created release commit and tag locally: $tag

Publish with:
  git push origin main
  git push origin $tag
EOF
