#!/bin/bash
set -euo pipefail
ARTIFACTS_DIR="${1:?Usage: copy_compose_resources.sh <artifacts-dir> <app-resources-dir>}"
APP_RESOURCES="${2:?Provide the app resources directory}"
if [ ! -d "$ARTIFACTS_DIR/compose-resources" ]; then
  echo "Missing Compose resources sidecar. Build the full distribution first." >&2
  exit 1
fi
mkdir -p "$APP_RESOURCES/compose-resources"
ditto "$ARTIFACTS_DIR/compose-resources" "$APP_RESOURCES/compose-resources"
echo "Copied Compose resources into the application bundle."
