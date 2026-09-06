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
    wait_for_http "http://localhost:9080/auth/realms/jhipster/.well-known/openid-configuration" "${WAIT_FOR_HTTP_TIMEOUT:-120}"
fi

#-------------------------------------------------------------------------------
# Run the application
#-------------------------------------------------------------------------------

java \
    -jar ./target/jhipster-control-center-*.jar \
    jhipster-control-center-*.jar \
    --spring.profiles.active="${JHI_PROFILE:-}" &
