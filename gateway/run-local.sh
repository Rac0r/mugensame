#!/usr/bin/env bash
# Starts a gateway config with the local Membrane distribution:
#   ./run-local.sh admin   admin API on http://localhost:2000/admin/...
#   ./run-local.sh now     aggregator on http://localhost:2000/now
set -euo pipefail
GATEWAY_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$GATEWAY_DIR/env.sh"

config="${1:-}"
case "$config" in
  admin|now) ;;
  *) echo "usage: $0 admin|now" >&2; exit 2 ;;
esac
: "${GITHUB_TOKEN:?set GITHUB_TOKEN in gateway/.env}"
if [ "$config" = admin ]; then
  : "${ADMIN_API_KEY:?set ADMIN_API_KEY in gateway/.env}"
fi

if [ ! -x "$MEMBRANE_HOME/membrane.sh" ]; then
  echo "no membrane.sh in MEMBRANE_HOME=$MEMBRANE_HOME - set MEMBRANE_HOME to the Membrane 7.7.0 folder" >&2
  exit 1
fi

cd "$GATEWAY_DIR"
exec "$MEMBRANE_HOME/membrane.sh" -c "$config.yaml"
