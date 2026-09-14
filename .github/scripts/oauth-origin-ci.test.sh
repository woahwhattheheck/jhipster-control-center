#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/run-app-ci.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

bash -n "$SCRIPT"

grep -Fq -- '--spring.security.oauth2.client.provider.oidc.authorization-uri=http://127.0.0.1:9080/auth/realms/jhipster/protocol/openid-connect/auth' "$SCRIPT" \
    || fail "OAuth CI must pin the browser authorization endpoint to the Cypress IPv4 origin"

grep -Fq -- '--spring.security.oauth2.client.registration.oidc.redirect-uri=http://127.0.0.1:7419/login/oauth2/code/oidc' "$SCRIPT" \
    || fail "OAuth CI must pin the callback to the Cypress IPv4 origin"

grep -Fq 'OIDC_DISCOVERY="http://localhost:9080/auth/realms/jhipster/.well-known/openid-configuration"' "$SCRIPT" \
    || fail "server-side OIDC discovery must remain on the issuer-matching localhost origin"

if grep -Fq -- '--spring.security.oauth2.client.provider.oidc.issuer-uri=http://127.0.0.1' "$SCRIPT"; then
    fail "do not rewrite the issuer; Spring must retain the discovery issuer"
fi

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
authorization = "--spring.security.oauth2.client.provider.oidc.authorization-uri=http://127.0.0.1:9080/auth/realms/jhipster/protocol/openid-connect/auth"
redirect = "--spring.security.oauth2.client.registration.oidc.redirect-uri=http://127.0.0.1:7419/login/oauth2/code/oidc"

if text.count(authorization) != 1:
    raise SystemExit("authorization override must occur exactly once")
if text.count(redirect) != 1:
    raise SystemExit("redirect override must occur exactly once")
if text.index(authorization) > text.index(redirect):
    raise SystemExit("authorization origin must be pinned before the callback argument")
PY

echo "PASS: OAuth browser authorization and callback share 127.0.0.1 while server discovery retains localhost"
