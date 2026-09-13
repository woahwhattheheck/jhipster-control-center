#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/run-app-ci.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
FAKEBIN="$WORKDIR/bin"
mkdir -p "$FAKEBIN"

[[ -f "$ROOT/src/main/docker/keycloak.yml" ]] || {
    echo "missing Keycloak compose fixture" >&2
    exit 1
}

write_exec() {
    local path="$1"
    cat > "$path"
    chmod +x "$path"
}

write_exec "$FAKEBIN/docker" <<'BIN'
#!/bin/bash
exit 0
BIN

write_exec "$FAKEBIN/java" <<'BIN'
#!/bin/bash
exit 0
BIN

write_exec "$FAKEBIN/sleep" <<'BIN'
#!/bin/bash
exit 0
BIN

write_exec "$FAKEBIN/curl" <<'BIN'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"/oauth2/authorization/oidc" ]]; then
        printf '%s\n%s' \
            "${AUTH_STATUS:-302}" \
            "${AUTH_LOCATION-http://localhost:9080/auth/realms/jhipster/protocol/openid-connect/auth?client_id=web_app}"
        exit 0
    fi
done
printf '%s\n' '{"issuer":"http://localhost:9080/auth/realms/jhipster"}'
exit 0
BIN

run_case() {
    local status="$1"
    local location="${2-http://localhost:9080/auth/realms/jhipster/protocol/openid-connect/auth?client_id=web_app}"
    set +e
    (
        cd "$ROOT"
        PATH="$FAKEBIN:/usr/bin:/bin" \
            AUTH_STATUS="$status" \
            AUTH_LOCATION="$location" \
            WAIT_FOR_HTTP_TIMEOUT=2 \
            JHI_APP=jhcc-static-oauth2 \
            JHI_PROFILE='dev, api-docs, static, oauth2' \
            bash "$SCRIPT" >/dev/null 2>&1
    )
    local rc=$?
    set -e
    printf '%s\n' "$rc"
}

[[ "$(run_case 302)" == "0" ]] || {
    echo "302 authorization redirect to Keycloak should pass preflight" >&2
    exit 1
}
[[ "$(run_case 302 '')" != "0" ]] || {
    echo "302 response without Location must fail preflight" >&2
    exit 1
}
[[ "$(run_case 302 'http://localhost:9080/not-the-authorization-endpoint')" != "0" ]] || {
    echo "302 response to an unrelated target must fail preflight" >&2
    exit 1
}
[[ "$(run_case 500)" != "0" ]] || {
    echo "500 authorization response must fail preflight" >&2
    exit 1
}
[[ "$(run_case 200)" != "0" ]] || {
    echo "200 authorization response must fail preflight" >&2
    exit 1
}

echo "oauth redirect preflight: valid Keycloak 302 passes; missing/unrelated Location and 200/500 fail"
