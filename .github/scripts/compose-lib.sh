# Compose V2 (`docker compose`) is what GitHub-hosted ubuntu-latest ships.
# The hyphenated docker-compose v1 binary is gone from those runners.
# Prefer V2; fall back to v1 so older local environments keep working.
docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Neither 'docker compose' (V2) nor 'docker-compose' (v1) is available" >&2
    return 1
  fi
}

# Poll an HTTP URL until it returns success. Used so Keycloak realm import
# finishes before Spring Boot fetches /.well-known/openid-configuration.
wait_for_http() {
  local url="$1"
  local timeout="${2:-${WAIT_FOR_HTTP_TIMEOUT:-120}}"
  local elapsed=0
  echo "Waiting for ${url} (timeout ${timeout}s)"
  while true; do
    if curl -sf --max-time 2 "$url" >/dev/null 2>&1; then
      echo "${url} is up after ${elapsed}s"
      return 0
    fi
    elapsed=$((elapsed + 2))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      echo "Timed out waiting for ${url}" >&2
      docker ps -a || true
      docker logs docker-keycloak-1 2>&1 | tail -80 || true
      return 1
    fi
    sleep 2
  done
}
