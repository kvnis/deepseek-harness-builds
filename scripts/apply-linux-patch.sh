#!/usr/bin/env bash
# Apply every patch in patches/ to a checkout of an upstream release tag.
#
# Patches apply in file-name order, each on top of the previous one. A patch may
# only list the files it touches, so the order in this directory is the order
# they land in. Pure insertions are not here: they live in
# scripts/linux-target-fixups.py, which runs after every patch.
#
# Each patch gets a strict `git apply` first. Upstream occasionally moves the
# context lines the hunks are anchored on without changing the intent (that is
# what broke every scheduled run between 2026-10-28 and 2026-10-30). When strict
# apply refuses, the checkout is reset to the tag, the earlier patches are
# replayed, and the failing one is retried with `patch --fuzz=2`. The result is
# verified before anyone builds on it:
#
#   * every file the patch creates exists,
#   * every line the patch adds is present in the patched tree,
#   * no .rej files and no conflict markers were left behind.
#
# A fuzz apply that lands in the wrong place still fails the build instead of
# shipping a wrong AppImage. Verification is the whole point of the fallback.
#
# Usage: scripts/apply-linux-patch.sh [upstream-dir] [patch-file...]
#        scripts/apply-linux-patch.sh --verify [upstream-dir] [patch-file...]
#
# Without patch files every patches/*.patch is used, in order.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

verify_only=false
if [[ ${1:-} == --verify ]]; then
  verify_only=true
  shift
fi

upstream=${1:-upstream}
shift || true

patches=()
if [[ $# -eq 0 ]]; then
  for candidate in "$root"/patches/*.patch; do
    patches+=("$candidate")
  done
else
  patches=("$@")
fi

[[ ${#patches[@]} -gt 0 ]] || { echo "apply-linux-patch: no patches found in $root/patches" >&2; exit 1; }
[[ -d $upstream ]] || { echo "apply-linux-patch: no such directory: $upstream" >&2; exit 1; }

for index in "${!patches[@]}"; do
  patch_file=${patches[index]}
  [[ -f $patch_file ]] || { echo "apply-linux-patch: no such patch: $patch_file" >&2; exit 1; }
  patches[index]=$(cd "$(dirname "$patch_file")" && pwd)/$(basename "$patch_file")
done

# The fuzz retry has to reset the worktree to the tag, so a dirty checkout would
# lose work silently. Refuse instead: the workflow always patches a fresh clone.
if [[ $verify_only == false ]] && { ! git -C "$upstream" diff --quiet || ! git -C "$upstream" diff --cached --quiet; }; then
  echo "apply-linux-patch: refusing to patch a checkout with local changes in $upstream" >&2
  exit 1
fi

verify() {
  python3 - "$upstream" "$1" <<'PY'
import os
import sys

upstream, patch = sys.argv[1], sys.argv[2]

current = None
created = set()
added = {}
pending_create = False


def target_of(raw, marker):
    path = raw[len(marker):].rstrip("\n")
    if path == "/dev/null":
        return "/dev/null"
    return path[2:] if path.startswith("b/") or path.startswith("a/") else path


with open(patch, encoding="utf-8", errors="surrogateescape") as handle:
    for raw in handle:
        if raw.startswith("diff --git "):
            current = None
            pending_create = False
        elif raw.startswith("--- "):
            pending_create = target_of(raw, "--- ") == "/dev/null"
        elif raw.startswith("+++ "):
            current = target_of(raw, "+++ ")
            if current == "/dev/null":
                current = None
            else:
                added.setdefault(current, [])
                if pending_create:
                    created.add(current)
        elif current and raw.startswith("+") and not raw.startswith("+++"):
            added[current].append(raw[1:].rstrip("\n"))

problems = []

for name, lines in sorted(added.items()):
    path = os.path.join(upstream, name)
    if name in created and not os.path.isfile(path):
        problems.append(f"{name}: created by the patch but missing")
        continue
    if not os.path.isfile(path):
        problems.append(f"{name}: missing")
        continue
    with open(path, encoding="utf-8", errors="surrogateescape") as handle:
        text = handle.read()
    if "<<<<<<<" in text or ">>>>>>>" in text:
        problems.append(f"{name}: conflict markers left behind")
    for line in lines:
        if not line.strip():
            continue
        if line not in text:
            problems.append(f"{name}: patched line missing: {line.strip()[:100]}")
            break

for base, _, names in os.walk(upstream):
    if "/.git" in base:
        continue
    for name in names:
        if name.endswith(".rej"):
            problems.append(os.path.join(base, name) + ": rejected hunk left behind")

if problems:
    print(f"apply-linux-patch: verification failed for {os.path.basename(patch)}", file=sys.stderr)
    for problem in problems:
        print("  " + problem, file=sys.stderr)
    sys.exit(1)

print(f"apply-linux-patch: verified {len(added)} patched files of {os.path.basename(patch)}")
PY
}

note() {
  echo "apply-linux-patch: $1"
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    echo "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

if [[ $verify_only == true ]]; then
  for patch_file in "${patches[@]}"; do
    verify "$patch_file"
  done
  note "Verified **${#patches[@]}** Linux patches."
  exit 0
fi

reset_to_tag() {
  git -C "$upstream" reset --quiet --hard
  git -C "$upstream" clean -fdq
}

apply_strict() {
  git -C "$upstream" apply --verbose "$1"
}

apply_with_fuzz() {
  local target=$1
  local dry_run
  dry_run=$(cd "$upstream" && patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch --dry-run < "$target" 2>&1) || {
    printf '%s\n' "$dry_run" >&2
    echo "apply-linux-patch: fuzz dry run failed for $(basename "$target"); the patch needs updating" >&2
    exit 1
  }
  printf '%s\n' "$dry_run"
  (cd "$upstream" && patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch < "$target")
}

reported=()
for index in "${!patches[@]}"; do
  patch_file=${patches[index]}
  name=$(basename "$patch_file")
  if apply_strict "$patch_file"; then
    reported+=("$name applied strictly")
    continue
  fi

  echo "apply-linux-patch: strict apply of $name failed, retrying with fuzz on a clean tag" >&2
  reset_to_tag
  for earlier in "${patches[@]:0:index}"; do
    apply_strict "$earlier" || {
      echo "apply-linux-patch: $(basename "$earlier") no longer applies strictly after the reset" >&2
      exit 1
    }
  done
  apply_with_fuzz "$patch_file"
  reported+=("$name applied with fuzz")
done

python3 "$root/scripts/linux-target-fixups.py" "$upstream"

for patch_file in "${patches[@]}"; do
  verify "$patch_file"
done

for line in "${reported[@]}"; do
  note "$line"
done

if [[ " ${reported[*]} " == *" with fuzz "* ]]; then
  note "Upstream moved context lines; at least one patch landed with fuzz offsets. Check the release notes before trusting the artifact."
fi
