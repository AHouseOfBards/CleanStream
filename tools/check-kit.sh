#!/bin/sh
# Fails if a kit file was edited inside the plugin. Change it in Campground-Coordination methodology/kit, then
# re-run install-kit.sh. Run by CI and by tests/gate.sh.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
manifest=$root/tools/kit.json
[ -f "$manifest" ] || { echo "check-kit: tools/kit.json is missing (install the kit with methodology/kit/install-kit.sh)"; exit 1; }
bad=0
for pair in $(sed -n 's/^ *"\([^"]*\)": "\([0-9a-f]\{64\}\)".*/\1=\2/p' "$manifest"); do
    f=${pair%%=*}; want=${pair#*=}
    if [ ! -f "$root/$f" ]; then echo "check-kit: missing $f"; bad=1; continue; fi
    got=$( (sha256sum "$root/$f" 2>/dev/null || shasum -a 256 "$root/$f") | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "check-kit: $f was edited in place"; bad=1; }
done
[ $bad -eq 0 ] && echo "check-kit: kit files match ($(sed -n 's/.*"source": "\(.*\)".*/\1/p' "$manifest"))"
exit $bad
