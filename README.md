set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

CRED_DIR="${HEALTHCHECK_CRED_DIR:-$HOME/.healthcheck}"
for f in credentials.yml vault_pass; do
  [[ -r "$CRED_DIR/$f" ]] || { echo "missing $CRED_DIR/$f (see README)" >&2; exit 2; }
done
if [[ "$(stat -c %a "$CRED_DIR/vault_pass")" != 600 ]]; then
  echo "$CRED_DIR/vault_pass must be mode 0600" >&2; exit 2
fi

playbook=healthcheck.yml
if [[ "${1:-}" == *.yml ]]; then playbook="$1"; shift; fi

exec ansible-playbook "$playbook" \
  -e "@$CRED_DIR/credentials.yml" \
  --vault-password-file "$CRED_DIR/vault_pass" \
  "$@"
