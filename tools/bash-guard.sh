#!/bin/sh
# PreToolUse hook on Bash. Rules that a CLAUDE.md line couldn't hold, so the harness holds them.
#
#   1. No heredocs. Bonfire has eleven recorded cases of a heredoc or `node -e` edit silently corrupting a file,
#      one of which shipped an unparseable manifest.json. Use the editor tool, or write a script file and run it.
#   2. No `git push` while the public guard fails (tools/guard-public.sh --push): design docs, private files,
#      secrets.
#
# Plain sh + grep, not Node: Node isn't installed on every agent's machine (it isn't on CleanStream's), and a guard
# that can't start enforces nothing while looking like it does. The hook payload is JSON, but the characters checked
# for (`<<`, `git push`) aren't escaped by JSON, so the raw text is enough. No parser is needed.
#
# Anything unexpected allows the command: a guard that blocks work because it can't read its own input gets turned
# off, and then nothing is enforced.

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

deny() {
    # $1 is plain text without double quotes or backslashes (it is embedded in JSON as is).
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
    exit 0
}

# Only the command itself: the payload also carries a description, which may legitimately mention these words.
# The value runs to the first quote that isn't escaped; a greedy match ran on into "description" (the kit test caught it).
command=$(printf '%s' "$payload" | sed -n -E 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
[ -n "$command" ] || exit 0

# 1. Heredoc: << or <<- followed by an optional quote and a delimiter word. Not <<< (a here-string) and not
#    $((1 << 3)) (a shift: a space then a digit).
if printf '%s' "$command" | grep -Eq '(^|[^<])<<-?[[:space:]]*(\\"|'"'"')?[A-Za-z_]'; then
    deny "Heredocs are blocked here (Campground kit rule: they have silently corrupted files and shipped a broken manifest). Write the content with the editor tool, or write a script file in the scratchpad and run it; for a commit message use git commit -F <file>. A here-string (<<<) is fine."
fi

# 2. Inline interpreter code that writes a file: node -e/--eval/-p and python -c. Same corruption class as a heredoc
#    (shell-mangled escapes inside code inside a string). Bonfire's eleven cases include node -e. Reading stays
#    allowed (node -e "console.log(...)"). This catches accidents, not someone determined to get past it.
#    Python's open() counts as a write only when its mode argument has w, a or x: open("a.txt") alone names a file
#    whose first letter can be "a", and the first draft denied that read (the kit test caught it).
if printf '%s' "$command" | grep -Eq '(^|[;&|[:space:]])(node|nodejs)(\.exe)?[[:space:]]+(-e|--eval|-p|--print)([[:space:]]|=)' \
    && printf '%s' "$command" | grep -Eq 'writeFileSync|appendFileSync|createWriteStream|writeFile\(|appendFile\(|renameSync|copyFileSync|rmSync|unlinkSync'; then
    deny "node -e that writes files is blocked here (same rule as heredocs). Write the script to a file in the scratchpad and run node on that file, or use the editor tool."
fi
if printf '%s' "$command" | grep -Eq '(^|[;&|[:space:]])(python3?|py)(\.exe)?[[:space:]]+(-[A-Za-z]*c)([[:space:]]|$)' \
    && printf '%s' "$command" | grep -Eq "open\([^)]*,[[:space:]]*(mode[[:space:]]*=[[:space:]]*)?[\\\\]*['\"][rbt]*[wax]|write_text|write_bytes|shutil\.|os\.(remove|rename|replace)"; then
    deny "python -c that writes files is blocked here (same rule as heredocs). Write the script to a file in the scratchpad and run python on that file, or use the editor tool."
fi

# 3. git push: the public guard on what would be pushed, then the plugin's own cheap pre-push checks
#    (gate_prepush in tests/gate.conf, if defined). Bonfire, 2026-09-10: bump, commit and push ran as one command, so a
#    broken manifest reached CI only after the tag existed. The cheapest check at the last moment.
if printf '%s' "$command" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'; then
    # Guard the repo being pushed, not the project dir: a workspace can hold several clones (GameTent's does), and
    # `git -C <dir> push` names another repo. Start from the payload's cwd, then follow -C.
    start=$(printf '%s' "$payload" | sed -n -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 | sed 's/\\\\/\//g')
    [ -n "$start" ] && [ -d "$start" ] || start=${CLAUDE_PROJECT_DIR:-$(pwd)}
    dashc=$(printf '%s' "$command" | sed -n -E 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:];&|]+)[[:space:]]+push.*/\1/p' | head -n 1 | sed -e 's/^\\"//' -e 's/\\"$//')
    if [ -n "$dashc" ]; then
        case "$dashc" in /*|[A-Za-z]:*) start=$dashc ;; *) start=$start/$dashc ;; esac
    fi
    repo=$(cd "$start" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
    guard="$repo/tools/guard-public.sh"
    if [ -f "$guard" ] && ! out=$(cd "$repo" && sh "$guard" --outgoing 2>&1); then
        reason=$(printf '%s' "$out" | tail -n 8 | tr '\n"\\' "   ")
        deny "tools/guard-public.sh refuses this push: $reason Fix it, run sh tools/guard-public.sh --outgoing, then push."
    fi
    if [ -f "$repo/tests/gate.conf" ]; then
        # step() here is a minimal stand-in for gate.sh's, so gate_prepush can use the same syntax.
        if ! out=$(cd "$repo" && (
                prepush_fail=0
                step() { _n=$1; shift; "$@" || { echo "pre-push check failed: $_n"; prepush_fail=1; }; }
                . ./tests/gate.conf >/dev/null 2>&1 || exit 0
                command -v gate_prepush >/dev/null 2>&1 || exit 0
                gate_prepush
                exit $prepush_fail
            ) 2>&1); then
            reason=$(printf '%s' "$out" | tail -n 8 | tr '\n"\\' "   ")
            deny "A pre-push check in tests/gate.conf (gate_prepush) failed: $reason Fix it, then push."
        fi
    fi
fi

exit 0
