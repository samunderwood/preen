#!/bin/zsh
# Publishes a Preen update with SamKit's shared release script; see the top of
# $SAMKIT_DIR/Tools/Release/release.sh for the options and what each Mac needs.
#   scripts/release.sh              a release
#   scripts/release.sh --dry-run    everything except uploading
#   scripts/release.sh --first      the very first release, when there is no appcast yet
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml first.
set -euo pipefail
samkit=${SAMKIT_DIR:-$HOME/Developer/SamKit}
if [[ ! -x $samkit/Tools/Release/release.sh ]]; then
    echo "SamKit isn't at $samkit. Clone github.com/samunderwood/samkit there, or set SAMKIT_DIR." >&2
    exit 1
fi
exec "$samkit/Tools/Release/release.sh" "${0:A:h}/release.conf" "$@"
