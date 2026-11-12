#!/usr/bin/env sh
# Build this LubeLogger fork and push it to the homelab zot registry, then
# (optionally) redeploy on nuc5. Modeled on putiomanager's build-and-push-image.sh.
#
#   Registry: docker-registry.olcese.com.ar/lubelogger
#   Tags:     <upstream version>-<git short sha>  (e.g. 1.7.4-e3a395b)  and  :latest
#   Deploy:   nuc5:/opt/apps/lubelogger  (compose tracks :latest)
#
# Usage:
#   ./scripts/build-and-push-image.sh
#   DEPLOY_AFTER_PUSH=0 ./scripts/build-and-push-image.sh   # push only
#   SCAN=0 ./scripts/build-and-push-image.sh                # skip Trivy
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REGISTRY="${REGISTRY:-docker-registry.olcese.com.ar}"
REGISTRY="${REGISTRY#http://}"
REGISTRY="${REGISTRY#https://}"
IMAGE_NAME="${IMAGE_NAME:-lubelogger}"
TAG="${TAG:-}"
PUSH_LATEST="${PUSH_LATEST:-1}"
PLATFORM="${PLATFORM:-linux/amd64}"
DEPLOY_AFTER_PUSH="${DEPLOY_AFTER_PUSH:-1}"
DEPLOY_HOST="${DEPLOY_HOST:-nuc5}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/apps/lubelogger}"

# Vulnerability scanning (Trivy). Set SCAN=0 to skip.
SCAN="${SCAN:-1}"
SCAN_SEVERITY="${SCAN_SEVERITY:-HIGH,CRITICAL}"
# Report-only by default: findings here come from upstream's .NET base image, which
# this fork doesn't control. Set SCAN_EXIT_CODE=1 to block the push on findings.
SCAN_EXIT_CODE="${SCAN_EXIT_CODE:-0}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"

# Upstream version from StaticHelper.VersionNumber, plus the fork commit.
VERSION="$(sed -n 's/.*const string VersionNumber = "\([^"]*\)".*/\1/p' "$REPO_ROOT/Helper/StaticHelper.cs")"
[ -n "$VERSION" ] || { echo "Could not read VersionNumber from Helper/StaticHelper.cs" >&2; exit 1; }
VCS_REF="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
  VCS_REF="${VCS_REF}-dirty"
fi
[ -n "$TAG" ] || TAG="${VERSION}-${VCS_REF}"

docker info >/dev/null 2>&1 || { echo "Docker is not running or is not reachable." >&2; exit 1; }

STATUS="$(curl -fsS -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${REGISTRY}/v2/" 2>/dev/null || true)"
[ -n "$STATUS" ] || { echo "Registry is not reachable at https://${REGISTRY}/v2/." >&2; exit 1; }

IMAGE="${REGISTRY}/${IMAGE_NAME}"
TAGS="-t ${IMAGE}:${TAG}"
[ "$PUSH_LATEST" = "1" ] && TAGS="$TAGS -t ${IMAGE}:latest"

echo "Building ${IMAGE}:${TAG} for ${PLATFORM}"
# shellcheck disable=SC2086
docker buildx build --platform "$PLATFORM" \
  --label "org.opencontainers.image.version=${VERSION}" \
  --label "org.opencontainers.image.revision=${VCS_REF}" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  $TAGS --load "$REPO_ROOT"

if [ "$SCAN" = "1" ]; then
  echo "Scanning ${IMAGE}:${TAG} for ${SCAN_SEVERITY} vulnerabilities..."
  if command -v trivy >/dev/null 2>&1; then
    trivy image --severity "$SCAN_SEVERITY" --exit-code "$SCAN_EXIT_CODE" \
      --ignore-unfixed --no-progress --scanners vuln "${IMAGE}:${TAG}"
  else
    # Scan an exported tar rather than mounting the Docker socket (works on Docker Desktop).
    cache="${HOME}/.cache/trivy"
    mkdir -p "$cache"
    docker save "${IMAGE}:${TAG}" -o "${cache}/scan-image.tar"
    set +e
    docker run --rm -v "${cache}:/root/.cache/trivy" "$TRIVY_IMAGE" image \
      --input /root/.cache/trivy/scan-image.tar \
      --severity "$SCAN_SEVERITY" --exit-code "$SCAN_EXIT_CODE" \
      --ignore-unfixed --no-progress --scanners vuln
    rc=$?
    set -e
    rm -f "${cache}/scan-image.tar"
    [ "$rc" = "0" ] || { echo "Vulnerability scan failed; not pushing." >&2; exit "$rc"; }
  fi
else
  echo "Skipping vulnerability scan (SCAN=0)."
fi

echo "Pushing ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"
[ "$PUSH_LATEST" = "1" ] && docker push "${IMAGE}:latest"

# Warm zot's CVE scanner so the registry UI shows results immediately. Non-fatal.
for t in "$TAG" latest; do
  curl -fsS -G "https://${REGISTRY}/v2/_zot/ext/search" \
    --data-urlencode "query={CVEListForImage(image:\"${IMAGE_NAME}:${t}\"){Summary{Count MaxSeverity}}}" \
    >/dev/null 2>&1 || true
done

if [ "$DEPLOY_AFTER_PUSH" = "1" ]; then
  echo "Deploying on ${DEPLOY_HOST}:${DEPLOY_PATH}"
  ssh "$DEPLOY_HOST" "cd ${DEPLOY_PATH} && sudo docker compose pull && sudo docker compose up -d"
fi

echo "Done: ${IMAGE}:${TAG}"
