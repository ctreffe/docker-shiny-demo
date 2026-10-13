#!/usr/bin/env bash
# Build and smoke-test the pipeline's exact checkout, then publish its image digest.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_hosting_context

test_container=""
cleanup() {
    # This is only the temporary smoke-test container created below.
    if [[ -n "$test_container" ]]; then
        docker rm --force "$test_container" >/dev/null 2>&1 || true
    fi
    cleanup_registry_login
}
trap cleanup EXIT
registry_login

# Include the pipeline ID as well as the commit: two builds of one commit may
# pick up different base-image updates and must not overwrite each other's tag.
image_tag="$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA-$CI_PIPELINE_ID"
docker build --pull \
    --label "org.opencontainers.image.revision=$CI_COMMIT_SHA" \
    --label "org.opencontainers.image.version=$CI_PIPELINE_ID" \
    --tag "$image_tag" .

# Test the built image without opening a host port or using the hosting network.
test_container="$(docker run --detach --read-only --cap-drop ALL \
    --security-opt no-new-privileges:true --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    --env 'GREETING_TEXT=Hello from the image smoke test!' "$image_tag")"
healthy=false
for attempt in {1..30}; do
    state="$(docker inspect --format '{{.State.Health.Status}}' "$test_container")"
    if [[ "$state" == healthy ]]; then healthy=true; break; fi
    if [[ "$state" == unhealthy ]]; then break; fi
    sleep 2
done
if [[ "$healthy" != true ]]; then
    docker logs --tail 100 "$test_container" >&2 || true
    fail "The image did not pass its health check. It has not been pushed."
fi
docker exec "$test_container" Rscript /opt/demo/probe.R \
    http://127.0.0.1:3838/ "Hello from the image smoke test!"

docker push "$image_tag"
# Pulling the published tag records the registry digest on this Docker daemon.
docker pull "$image_tag"
APP_IMAGE="$(docker image inspect --format '{{json .RepoDigests}}' "$image_tag" |
    python3 -c 'import json, sys; prefix = sys.argv[1] + "@sha256:"; matches = [item for item in json.load(sys.stdin) if item.startswith(prefix)]; assert len(matches) == 1, "Expected one matching registry digest"; print(matches[0])' "$CI_REGISTRY_IMAGE")"

# GitLab reads this artifact and supplies these values to the deployment job.
# Only non-secret release metadata belongs in a dotenv artifact.
printf 'APP_IMAGE=%s\nRELEASE_COMMIT=%s\nRELEASE_PIPELINE_ID=%s\n' \
    "$APP_IMAGE" "$CI_COMMIT_SHA" "$CI_PIPELINE_ID" > release.env
printf 'Published release image: %s\n' "$APP_IMAGE"
