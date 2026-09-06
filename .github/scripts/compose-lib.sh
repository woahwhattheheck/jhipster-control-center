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
