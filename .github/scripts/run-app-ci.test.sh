#!/bin/bash
# Regression for Application CI e2e: ubuntu-latest has Compose V2 only.
# docker-compose (v1) is missing, so consul/oauth2 jobs never start their
# sidecars and Cypress then fails to reach http://localhost:7419/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/run-app-ci.sh"
LIB="$ROOT/.github/scripts/compose-lib.sh"
PKG="$ROOT/package.json"
KC="$ROOT/src/main/docker/keycloak.yml"
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

assert_file() {
  [[ -f "$1" ]] || { fail "missing $1"; return; }
  pass "exists $1"
}

assert_file "$SCRIPT"
assert_file "$LIB"
assert_file "$PKG"
assert_file "$KC"

if grep -qE '^set -e' "$SCRIPT"; then
  pass "run-app-ci.sh uses set -e so a compose failure fails the job"
else
  fail "run-app-ci.sh must enable set -e; otherwise missing compose is swallowed and Cypress reports a misleading baseUrl failure"
fi

if grep -qE '^\. .*compose-lib\.sh|"\$SCRIPT_DIR/compose-lib.sh"' "$SCRIPT" || grep -q 'compose-lib.sh' "$SCRIPT"; then
  pass "run-app-ci.sh sources compose-lib.sh"
else
  fail "run-app-ci.sh must source compose-lib.sh"
fi

# Direct command-position docker-compose (leading whitespace, not a comment)
# is the measured CI failure. Fallback inside docker_compose() is allowed.
if grep -E '^[[:space:]]+docker-compose[[:space:]]' "$SCRIPT" >/dev/null; then
  fail "run-app-ci.sh still invokes docker-compose directly (v1 binary missing on ubuntu-latest)"
else
  pass "run-app-ci.sh does not invoke docker-compose as a top-level command"
fi

if grep -q 'docker_compose ' "$SCRIPT"; then
  pass "run-app-ci.sh starts sidecars through docker_compose"
else
  fail "run-app-ci.sh must call docker_compose for registry/consul/keycloak"
fi

if grep -q "docker compose" "$LIB" && grep -q 'docker compose version' "$LIB"; then
  pass "compose-lib.sh prefers Docker Compose V2"
else
  fail "compose-lib.sh must probe 'docker compose version' first"
fi

python3 - "$PKG" <<'PY'
import json, sys
pkg = json.load(open(sys.argv[1]))
bad = []
good = []
for k, v in pkg.get("scripts", {}).items():
    if not k.startswith("docker:"):
        continue
    if "docker-compose " in v:
        bad.append(f"{k}={v}")
    if "docker compose " in v:
        good.append(k)
if bad:
    print("FAIL npm scripts still use hyphenated docker-compose: " + "; ".join(bad))
    sys.exit(1)
if len(good) < 6:
    print("FAIL expected docker compose V2 in the six docker up/down scripts, found: " + ",".join(good))
    sys.exit(1)
print("PASS npm docker scripts use docker compose V2 (%d scripts)" % len(good))
PY
if [[ $? -eq 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
fi

if grep -q 'quay.io/keycloak/keycloak' "$KC" && ! grep -q 'jboss/keycloak' "$KC"; then
  pass "keycloak.yml uses quay.io/keycloak (jboss/keycloak is gone from Docker Hub)"
else
  fail "keycloak.yml must not use the removed jboss/keycloak image"
fi

if grep -q 'KC_HOSTNAME=localhost' "$KC"; then
  pass "keycloak.yml pins KC_HOSTNAME=localhost so OIDC redirects stay on the host"
else
  fail "keycloak.yml must set KC_HOSTNAME=localhost (container hostname breaks Cypress cy.request)"
fi

SPA="$ROOT/src/main/java/tech/jhipster/controlcenter/web/filter/SpaWebFilter.java"
assert_file "$SPA"
if grep -q '!path.startsWith("/oauth2")' "$SPA"; then
  pass "SpaWebFilter leaves /oauth2/authorization/oidc for Spring Security"
else
  fail "SpaWebFilter must not rewrite /oauth2 to index.html (oauth2 e2e cy.request hangs otherwise)"
fi

# --- functional tests of docker_compose with fake binaries ---
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
FAKE_LOG="$WORKDIR/calls.log"
export FAKE_LOG

write_exec() {
  local path="$1"
  cat > "$path"
  chmod +x "$path"
}

# V2 present: must call `docker compose`, never the v1 binary.
V2_BIN="$WORKDIR/v2"
mkdir -p "$V2_BIN"
write_exec "$V2_BIN/docker" <<'BIN'
#!/bin/bash
echo "v2 $*" >> "$FAKE_LOG"
if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
  echo "Docker Compose version v2.29.0"
  exit 0
fi
exit 0
BIN
write_exec "$V2_BIN/docker-compose" <<'BIN'
#!/bin/bash
echo "v1 $*" >> "$FAKE_LOG"
exit 0
BIN
: > "$FAKE_LOG"
# shellcheck source=compose-lib.sh
. "$LIB"
PATH="$V2_BIN:$PATH" docker_compose -f src/main/docker/consul.yml up -d
if grep -q '^v2 compose -f src/main/docker/consul.yml up -d$' "$FAKE_LOG" && ! grep -q '^v1 ' "$FAKE_LOG"; then
  pass "docker_compose prefers V2 when both binaries exist"
else
  fail "V2 preference broken; log=$(cat "$FAKE_LOG")"
fi

# V2 absent, v1 present: fall back.
V1_BIN="$WORKDIR/v1"
mkdir -p "$V1_BIN"
write_exec "$V1_BIN/docker" <<'BIN'
#!/bin/bash
# no compose subcommand
exit 1
BIN
write_exec "$V1_BIN/docker-compose" <<'BIN'
#!/bin/bash
echo "v1 $*" >> "$FAKE_LOG"
exit 0
BIN
: > "$FAKE_LOG"
PATH="$V1_BIN:$PATH" docker_compose -f src/main/docker/keycloak.yml up -d
if grep -q '^v1 -f src/main/docker/keycloak.yml up -d$' "$FAKE_LOG"; then
  pass "docker_compose falls back to v1 when V2 is missing"
else
  fail "v1 fallback broken; log=$(cat "$FAKE_LOG")"
fi

# Neither present: must fail, not continue into Java/Cypress.
NONE_BIN="$WORKDIR/none"
mkdir -p "$NONE_BIN"
: > "$FAKE_LOG"
if PATH="$NONE_BIN" docker_compose -f src/main/docker/consul.yml up -d 2>/dev/null; then
  fail "docker_compose must fail when neither V2 nor v1 exists"
else
  pass "docker_compose fails closed when no compose implementation exists"
fi

# Sidecar start for a consul job must invoke compose, and must not reach java
# if compose is missing (set -e on run-app-ci.sh).
NONE_PATH="$WORKDIR/none-path"
mkdir -p "$NONE_PATH"
write_exec "$NONE_PATH/java" <<'BIN'
#!/bin/bash
echo "java-ran $*" >> "$FAKE_LOG"
exit 0
BIN
write_exec "$NONE_PATH/sleep" <<'BIN'
#!/bin/bash
exit 0
BIN
write_exec "$NONE_PATH/docker" <<'BIN'
#!/bin/bash
echo "bare-docker $*" >> "$FAKE_LOG"
exit 1
BIN
: > "$FAKE_LOG"
set +e
PATH="$NONE_PATH" JHI_APP=jhcc-consul JHI_PROFILE='dev, api-docs, consul' \
  bash "$SCRIPT" >/dev/null 2>&1
status=$?
set -e
if [[ $status -ne 0 ]] && ! grep -q '^java-ran ' "$FAKE_LOG"; then
  pass "run-app-ci.sh exits before java when compose is missing (status=$status)"
else
  fail "run-app-ci.sh launched java or succeeded without compose; status=$status log=$(cat "$FAKE_LOG")"
fi

# oauth2 jobs must wait for Keycloak OIDC before launching Java.
if grep -q 'wait_for_http' "$SCRIPT" && grep -q 'openid-configuration' "$SCRIPT"; then
  pass "run-app-ci.sh waits for Keycloak OIDC discovery before Java"
else
  fail "run-app-ci.sh must wait_for_http the Keycloak openid-configuration URL"
fi

if grep -q 'wait_for_http' "$LIB" && grep -q 'curl -sf' "$LIB"; then
  pass "compose-lib.sh wait_for_http polls with curl"
else
  fail "compose-lib.sh must define wait_for_http using curl"
fi

OAUTH_BIN="$WORKDIR/oauth"
mkdir -p "$OAUTH_BIN"
write_exec "$OAUTH_BIN/docker" <<'BIN'
#!/bin/bash
echo "v2 $*" >> "$FAKE_LOG"
if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
  echo "Docker Compose version v2.29.0"
  exit 0
fi
if [[ "${1:-}" == "ps" ]]; then
  exit 0
fi
exit 0
BIN
write_exec "$OAUTH_BIN/curl" <<'BIN'
#!/bin/bash
echo "curl $*" >> "$FAKE_LOG"
exit 0
BIN
write_exec "$OAUTH_BIN/java" <<'BIN'
#!/bin/bash
echo "java-ran $*" >> "$FAKE_LOG"
exit 0
BIN
write_exec "$OAUTH_BIN/sleep" <<'BIN'
#!/bin/bash
exit 0
BIN
: > "$FAKE_LOG"
PATH="$OAUTH_BIN:/usr/bin:/bin" JHI_APP=jhcc-static-oauth2 JHI_PROFILE='dev, api-docs, static, oauth2' \
  bash "$SCRIPT" >/dev/null 2>&1
if grep -q 'openid-configuration' "$FAKE_LOG" && grep -q '^java-ran ' "$FAKE_LOG"; then
  pass "oauth2 path waits for OIDC then starts java"
else
  fail "oauth2 path did not wait for OIDC before java; log=$(cat "$FAKE_LOG")"
fi

# If OIDC never comes up, java must not start.
write_exec "$OAUTH_BIN/curl" <<'BIN'
#!/bin/bash
echo "curl-fail $*" >> "$FAKE_LOG"
exit 1
BIN
: > "$FAKE_LOG"
set +e
PATH="$OAUTH_BIN:/usr/bin:/bin" WAIT_FOR_HTTP_TIMEOUT=4 JHI_APP=jhcc-static-oauth2 JHI_PROFILE='dev, api-docs, static, oauth2' \
  bash "$SCRIPT" >/dev/null 2>&1
oauth_status=$?
set -e
if [[ $oauth_status -ne 0 ]] && ! grep -q '^java-ran ' "$FAKE_LOG"; then
  pass "oauth2 path fails closed when Keycloak OIDC never becomes ready (status=$oauth_status)"
else
  fail "oauth2 path started java without OIDC; status=$oauth_status log=$(cat "$FAKE_LOG")"
fi

echo
echo "$PASS passed, $FAIL failed"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
