#!/bin/bash
set -euo pipefail

# Absolute path to the repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="$ROOT_DIR/deploy.sh"

export LC_ALL=C

# Gather all .registry items
temp_file=$(mktemp)
# Sort to ensure consistent order (optional, but good for git diffs)
for reg_file in "$ROOT_DIR"/projects/*/.registry; do
    if [ -f "$reg_file" ]; then
        # remove trailing \r if any
        content=$(cat "$reg_file" | tr -d '\r')
        echo "    \"$content\"" >> "$temp_file"
    fi
done

# Read it into a variable
contents=$(cat "$temp_file")
rm -f "$temp_file"

# Process with awk
# Windows /r tolerant regex
awk -v c="$contents" '
/^REGISTRY=\(/ || /^REGISTRY=\(\r?$/ {
    print $0
    if (c != "") { print c }
    in_reg=1
    next
}
in_reg && (/^\)/ || /^\)\r?$/) {
    in_reg=0
    print $0
    next
}
in_reg { next }
{ print }
' "$DEPLOY_SCRIPT" > "$DEPLOY_SCRIPT.tmp"

mv "$DEPLOY_SCRIPT.tmp" "$DEPLOY_SCRIPT"

echo "[INFO] deploy.sh registry has been auto-updated based on project .registry files."
