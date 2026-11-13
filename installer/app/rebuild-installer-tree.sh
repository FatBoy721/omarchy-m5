#!/bin/bash
# Rebuild the patched installer tree exactly as installer-image.yml does:
# omacom/omarchy-mac-installer c07e54c, then installer/patches (tree pinned
# below), then each named extra set installer/patches-<name> in order, each
# checked against its own TREE file.
#
# usage: rebuild-installer-tree.sh DEST [SET...]   e.g. DEST upstream-27.3 j714s
set -euo pipefail

INSTALLER_REPO=https://github.com/omacom/omarchy-mac-installer
INSTALLER_BASE=c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9
# c07e54c + installer/patches (0001-0019)
INSTALLER_TREE=7f2f54c09928de609f1d4496e8a49dafc1418933

fail() { echo "rebuild-installer-tree: $*" >&2; exit 1; }
(( $# >= 1 )) || fail "usage: rebuild-installer-tree.sh DEST [SET...]"
dest=$1; shift
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ ! -e $dest ]] || fail "$dest already exists"

am() {
  git -C "$dest" -c user.name=omarchy-m5 -c user.email=omarchy-m5@localhost \
    am --quiet --committer-date-is-author-date "$@"
}

git clone --quiet "$INSTALLER_REPO" "$dest"
git -C "$dest" checkout --quiet -b j714s "$INSTALLER_BASE"
am "$here"/patches/*.patch
[[ $(git -C "$dest" rev-parse 'HEAD^{tree}') == "$INSTALLER_TREE" ]] || fail "installer/patches tree differs"
for set in "$@"; do
  [[ $set =~ ^[a-z0-9][a-z0-9.-]*$ ]] || fail "bad patch set name: $set"
  set_dir=$here/patches-$set
  [[ -f $set_dir/TREE ]] || fail "no installer/patches-$set/TREE"
  am "$set_dir"/*.patch
  want=$(tr -d '[:space:]' < "$set_dir/TREE")
  got=$(git -C "$dest" rev-parse 'HEAD^{tree}')
  [[ $got == "$want" ]] || fail "patches-$set: tree $got, TREE pins $want"
done
[[ -z $(git -C "$dest" status --porcelain) ]] || fail "the tree is not clean"
git -C "$dest" log --oneline -3
echo "tree=$(git -C "$dest" rev-parse 'HEAD^{tree}') commit=$(git -C "$dest" rev-parse HEAD)"
