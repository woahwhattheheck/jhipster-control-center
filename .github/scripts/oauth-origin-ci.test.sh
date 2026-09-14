#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/run-app-ci.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

bash -n "$SCRIPT"

grep -Fq 'EXPECTED_AUTHORIZATION_ENDPOINT="http://127.0.0.1:9080/auth/realms/jhipster/protocol/openid-connect/auth"' "$SCRIPT" \
    || fail "OAuth CI must define the browser authorization endpoint on the Cypress IPv4 origin"

grep -Fq -- '--spring.security.oauth2.client.provider.oidc.authorization-uri=${EXPECTED_AUTHORIZATION_ENDPOINT}' "$SCRIPT" \
    || fail "Spring authorization override must consume the exact browser authorization endpoint"

grep -Fq -- '--spring.security.oauth2.client.registration.oidc.redirect-uri=http://127.0.0.1:7419/login/oauth2/code/oidc' "$SCRIPT" \
    || fail "OAuth CI must pin the callback to the Cypress IPv4 origin"

grep -Fq 'OIDC_DISCOVERY="http://localhost:9080/auth/realms/jhipster/.well-known/openid-configuration"' "$SCRIPT" \
    || fail "server-side OIDC discovery must remain on the issuer-matching localhost origin"

grep -Fq 'EXPECTED_ISSUER="http://localhost:9080/auth/realms/jhipster"' "$SCRIPT" \
    || fail "server-side issuer equality must remain on localhost"

grep -Fq 'auth_location_base" != "$EXPECTED_AUTHORIZATION_ENDPOINT"' "$SCRIPT" \
    || fail "redirect preflight must validate the explicit IPv4 authorization endpoint"

if grep -Fq 'expected_auth_location="${EXPECTED_ISSUER}/protocol/openid-connect/auth"' "$SCRIPT"; then
    fail "redirect preflight must not derive a browser endpoint from the localhost issuer"
fi

if grep -Fq -- '--spring.security.oauth2.client.provider.oidc.issuer-uri=http://127.0.0.1' "$SCRIPT"; then
    fail "do not rewrite the issuer; Spring must retain the discovery issuer"
fi

if grep -Fq '${ath_status}' "$SCRIPT"; then
    fail "authorization status diagnostics must use auth_status"
fi

grep -Fq 'returned HTTP ${auth_status}; expected 302' "$SCRIPT" \
    || fail "authorization status diagnostics must report auth_status"

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
authorization_constant = 'EXPECTED_AUTHORIZATION_ENDPOINT="http://127.0.0.1:9080/auth/realms/jhipster/protocol/openid-connect/auth"'
authorization_arg = '--spring.security.oauth2.client.provider.oidc.authorization-uri=${EXPECTED_AUTHORIZATION_ENDPOINT}'
redirect = '--spring.security.oauth2.client.registration.oidc.redirect-uri=http://127.0.0.1:7419/login/oauth2/code/oidc'
preflight = 'auth_location_base" != "$EXPECTED_AUTHORIZATION_ENDPOINT"'

for needle, label in (
    (authorization_constant, "authorization constant"),
    (authorization_arg, "authorization override"),
    (redirect, "callback override"),
    (preflight, "authorization preflight"),
):
    if text.count(needle) != 1:
        raise SystemExit(f"{label} must occur exactly once")

if text.index(authorization_arg) > text.index(redirect):
    raise SystemExit("authorization origin must be pinned before the callback argument")
if text.index(preflight) < text.index("auth_location_base="):
    raise SystemExit("preflight comparison must consume the parsed redirect base")
PY

echo "PASS: localhost issuer/discovery and IPv4 browser authorization/callback compose with one redirect preflight"
