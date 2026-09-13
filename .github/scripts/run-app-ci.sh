#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=compose-lib.sh
. "$SCRIPT_DIR/compose-lib.sh"

#-------------------------------------------------------------------------------
# Start docker container
#-------------------------------------------------------------------------------

if [[ "${JHI_APP:-}" == *"eureka"* ]] && [[ -a src/main/docker/jhipster-registry.yml ]]; then
    docker_compose -f src/main/docker/jhipster-registry.yml up -d
    sleep 10
    docker ps -a
fi

if [[ "${JHI_APP:-}" == *"consul"* ]] && [[ -a src/main/docker/consul.yml ]]; then
    docker_compose -f src/main/docker/consul.yml up -d
    sleep 10
    docker ps -a
fi

if [[ "${JHI_APP:-}" == *"oauth2"* ]] && [[ -a src/main/docker/keycloak.yml ]]; then
    docker_compose -f src/main/docker/keycloak.yml up -d
    docker ps -a
    # Keycloak 26 realm import is slower than the old 10s sleep. Spring Boot
    # fetches the OIDC discovery document during context refresh, so the app
    # never binds :7419 if we start Java first.
    OIDC_DISCOVERY="http://localhost:9080/auth/realms/jhipster/.well-known/openid-configuration"
    wait_for_http "$OIDC_DISCOVERY" "${WAIT_FOR_HTTP_TIMEOUT:-120}"
    # Security 5.4 ClientRegistrations.withProviderConfiguration Assert.state
    # requires discovery.issuer == spring.security.oauth2.client.provider.oidc.issuer-uri.
    # Keycloak hostname v2 with KC_HOSTNAME=http://localhost:9080 (no /auth)
    # advertised issuer=http://localhost:9080/realms/jhipster and Java never bound.
    EXPECTED_ISSUER="http://localhost:9080/auth/realms/jhipster"
    issuer="$(curl -sf --max-time 5 "$OIDC_DISCOVERY" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("issuer",""))')"
    if [[ "$issuer" != "$EXPECTED_ISSUER" ]]; then
        echo "OIDC issuer mismatch: got '${issuer}' want '${EXPECTED_ISSUER}'" >&2
        echo "Keycloak KC_HOSTNAME must include the /auth relative path." >&2
        exit 1
    fi
    echo "OIDC issuer=${issuer}"
fi

#-------------------------------------------------------------------------------
# Run the application
#-------------------------------------------------------------------------------

java \
    -jar ./target/jhipster-control-center-*.jar \
    jhipster-control-center-*.jar \
    --spring.profiles.active="${JHI_PROFILE:-}" &

# Cypress only verifies :7419 when the e2e step starts. Fail here if the
# process never binds, and (oauth2) if the authorization redirect is not real.
wait_for_http "http://localhost:7419/" "${WAIT_FOR_HTTP_TIMEOUT:-120}"
if [[ "${JHI_APP:-}" == *"oauth2"* ]]; then
    echo "=== GET /oauth2/authorization/oidc ==="
    if ! auth_status="$(
        curl -sS --max-time 8 --max-redirs 0 -o /dev/null \
            -w "%{http_code}" \
            "http://localhost:7419/oauth2/authorization/oidc"
    )"; then
        echo "oauth2 authorization endpoint did not respond" >&2
        tail -120 target/jhipster-control-center.log >&2 || true
        exit 1
    fi
    if [[ "$auth_status" != "302" ]]; then
        echo "oauth2 authorization endpoint returned HTTP ${auth_status}; expected 302" >&2
        tail -120 target/jhipster-control-center.log >&2 || true
        exit 1
    fi
    echo "oauth2 authorization redirect status=${auth_status}"
fi
