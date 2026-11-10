#!/bin/sh
# Keeps what must stay private out of a public plugin repo. Run by the bash guard before `git push`, by the git
# pre-push hook, by tests/gate.sh and by CI.
#
#   sh tools/guard-public.sh --tree       every tracked file (CI and the gate)
#   sh tools/guard-public.sh --outgoing   only commits not yet on the upstream branch: their files, added lines and
#                                         commit messages (before a push)
#
# Fails on:
#   - private paths: design docs, methodology, *.private.md, CLAUDE.md, CLAUDE.local.md, local Claude settings;
#   - secrets: API keys or tokens with a real-looking value, Jellyfin Token="…", private keys, GitHub tokens;
#   - personal e-mail addresses (noreply and example addresses are fine);
#   - private IP addresses, when GUARD_IPS=1 in tools/guard-public.conf (a plugin that logs real traffic should set it).
# A line containing `guard:allow` is skipped (for test fixtures such as a fake key in a redaction test).
#
# Exit 0 clean, 1 something found (each finding printed), 2 usage. Needs sh, git, grep, sed.

set -u
mode=${1:-}
case "$mode" in --tree|--outgoing) ;; *) echo "usage: sh tools/guard-public.sh --tree|--outgoing" >&2; exit 2 ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "guard-public: not in a git repo" >&2; exit 2; }
cd "$root" || exit 2

# Per-plugin settings (optional): GUARD_IPS=1, EXTRA_PRIVATE_PATHS='^notes/|^scratch/'.
GUARD_IPS=0
EXTRA_PRIVATE_PATHS=
[ -f tools/guard-public.conf ] && . ./tools/guard-public.conf

# CLAUDE.md too (owner, 2026-11-10, #13): "claude.md can be shared between agents, but not on any public repo". The
# shared copy lives in Campground-Coordination agents/<plugin-id>/CLAUDE.md.
private_paths='(^|/)design/|(^|/)methodology/|\.private\.md$|(^|/)CLAUDE(\.local)?\.md$|(^|/)\.claude/settings\.local\.json$'
[ -n "$EXTRA_PRIVATE_PATHS" ] && private_paths="$private_paths|$EXTRA_PRIVATE_PATHS"

secrets='(api_?key|access_?token|x-(emby|mediabrowser)-token|password|passwd|client_?secret)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9+/_-]{20,}|Token="[A-Za-z0-9]{20,}"|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}'
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
email_ok='users\.noreply\.github\.com|noreply@|@example\.(com|org|net)|@localhost'
ips='(^|[^0-9.])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'

found=0
report() { echo "guard-public: $1"; found=1; }

# Prints "where<TAB>text" lines to scan, for the chosen mode.
lines() {
    if [ "$mode" = "--tree" ]; then
        git grep -n -I -E -i -e '.' -- . 2>/dev/null | sed 's/:/\t/2' | sed 's/:/ line /'
    else
        git diff -U0 --no-color "$(outgoing_base)" HEAD -- . 2>/dev/null | awk '
            /^\+\+\+ b\// { file = substr($0, 7); next }
            /^\+/ && !/^\+\+\+/ { print file "\t" substr($0, 2) }'
        git log --format='commit %h message%x09%B' $(outgoing_log) 2>/dev/null | grep -v '^$'
    fi
}

files() {
    if [ "$mode" = "--tree" ]; then git ls-files; else git diff --name-only --diff-filter=AMR "$(outgoing_base)" HEAD -- .; fi
}

# The commit (or tree) the push starts from. With no upstream and no remote branch in common, nothing is on the
# remote yet: compare against the empty tree, so the root commit is scanned too. (Using `<root>..HEAD` skipped the
# root commit, which is the whole first push of a new repo: GameTent's, FieldGuide's and Trailhead's revivals.)
outgoing_base() {
    if up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
        git merge-base HEAD "$up" 2>/dev/null && return
    fi
    base=
    for r in $(git for-each-ref --format='%(refname)' refs/remotes); do
        base=$(git merge-base HEAD "$r" 2>/dev/null) && [ -n "$base" ] && { echo "$base"; return; }
    done
    git hash-object -t tree /dev/null
}

# The commits whose messages the push carries: base..HEAD, or every commit when nothing is on the remote.
outgoing_log() {
    base=$(outgoing_base)
    if [ "$(git cat-file -t "$base" 2>/dev/null)" = "tree" ]; then echo HEAD; else echo "$base..HEAD"; fi
}

# 1. Private paths.
files | grep -E "$private_paths" | while read -r f; do echo "guard-public: private file would be public: $f"; done | grep . && found=1

# 2-4. Contents.
scan=$(lines | grep -v 'guard:allow')
hits=$(printf '%s\n' "$scan" | grep -E -i "$secrets")
[ -n "$hits" ] && { printf '%s\n' "$hits" | sed 's/^/guard-public: secret: /' | cut -c1-200; found=1; }

hits=$(printf '%s\n' "$scan" | grep -E "$email" | grep -E -v -i "$email_ok")
[ -n "$hits" ] && { printf '%s\n' "$hits" | sed 's/^/guard-public: e-mail address: /' | cut -c1-200; found=1; }

if [ "$GUARD_IPS" = "1" ]; then
    hits=$(printf '%s\n' "$scan" | grep -E "$ips")
    [ -n "$hits" ] && { printf '%s\n' "$hits" | sed 's/^/guard-public: private IP address: /' | cut -c1-200; found=1; }
fi

if [ $found -eq 0 ]; then echo "guard-public: clean ($mode)"; fi
exit $found
