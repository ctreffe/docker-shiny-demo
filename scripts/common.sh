#!/usr/bin/env bash
# Shared helpers keep the three CI scripts readable. They do not run a job by themselves.

# Keep track only of a directory created by this script, never an inherited login.
registry_config_dir=""

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_variables() {
    local variable
    for variable in "$@"; do
        # ${!variable} reads the value of a variable whose name is in $variable.
        [[ -n "${!variable:-}" ]] || fail "Set the required variable: $variable"
    done
}

require_hosting_context() {
    # Check these conditions inside the script too: job rules alone are not a guard
    # when someone copies a command into another job or runs a script by hand.
    [[ "${HOSTING_ENABLED:-false}" == true ]] || fail "Hosting is not enabled."
    require_variables CI_PROJECT_DIR CI_COMMIT_SHA CI_PIPELINE_ID CI_DEFAULT_BRANCH CI_COMMIT_BRANCH
    [[ "${CI_COMMIT_REF_PROTECTED:-false}" == true ]] || fail "Use a protected branch."
    [[ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]] || fail "Use the default branch."
    case "${CI_PIPELINE_SOURCE:-}" in
        push|web) ;;
        *) fail "Only push or manually started pipelines can build a hosting release." ;;
    esac
    [[ "$CI_COMMIT_SHA" =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ ]] || fail "Invalid commit SHA."
    [[ "$CI_PIPELINE_ID" =~ ^[0-9]+$ ]] || fail "Invalid pipeline ID."
    cd "$CI_PROJECT_DIR"
    [[ "$(git rev-parse HEAD)" == "$CI_COMMIT_SHA" ]] || fail "The checkout is not the pipeline commit."
}

prepare_deployment_directory() {
    require_variables DEPLOY_ROOT DEPLOY_DIR CI_PROJECT_DIR
    local root target checkout
    [[ "$DEPLOY_ROOT" == /* && "$DEPLOY_DIR" == /* ]] || fail "Deployment paths must be absolute."
    # The platform supplies an existing root. The job creates only the app's
    # directory below it, never a new platform root or a directory elsewhere.
    root="$(realpath -e -- "$DEPLOY_ROOT")" || fail "DEPLOY_ROOT must already exist."
    [[ -d "$root" && "$root" != / ]] || fail "Choose an existing dedicated deployment root."
    # -m resolves existing parent symlinks and '..' even when the app folder is
    # still missing. Check that resolved destination BEFORE running mkdir.
    target="$(realpath -m -- "$DEPLOY_DIR")" || fail "Cannot resolve DEPLOY_DIR."
    [[ "$target" == "$root/"* ]] || fail "DEPLOY_DIR must be a strict child of DEPLOY_ROOT."
    checkout="$(realpath -e -- "$CI_PROJECT_DIR")" || fail "Cannot resolve the CI checkout."
    [[ "$target" != "$checkout" && "$target" != "$checkout/"* && "$checkout" != "$target/"* ]] ||
        fail "Keep the deployment directory separate from the CI checkout."
    [[ ! -e "$target" || -d "$target" ]] || fail "DEPLOY_DIR must be a directory, not a file."
    [[ ! -L "$target/compose.json" && ! -L "$target/release.txt" ]] || fail "Release files must not be symbolic links."

    # Missing app folders are private to this job's user. mkdir -p also makes
    # retries harmless and preserves the permissions and contents of existing dirs.
    (
        umask 077
        mkdir -p -- "$target"
    ) || fail "Cannot create DEPLOY_DIR; the runner needs write permission below DEPLOY_ROOT."
    [[ "$(realpath -e -- "$target")" == "$target" ]] || fail "The deployment path changed during preparation."
    [[ -d "$target" && -w "$target" && -x "$target" ]] || fail "The runner cannot write to DEPLOY_DIR."
    # Command substitution in deploy.sh captures this one canonical path.
    printf '%s\n' "$target"
}

registry_login() {
    require_variables CI_REGISTRY CI_REGISTRY_USER CI_REGISTRY_PASSWORD CI_REGISTRY_IMAGE
    # Each job has its own short-lived Docker configuration. Never log the password
    # or write registry credentials to the persistent deployment directory.
    registry_config_dir="$(mktemp -d)"
    DOCKER_CONFIG="$registry_config_dir"
    export DOCKER_CONFIG
    printf '%s' "$CI_REGISTRY_PASSWORD" |
        docker login "$CI_REGISTRY" --username "$CI_REGISTRY_USER" --password-stdin
}

cleanup_registry_login() {
    if [[ -n "$registry_config_dir" ]]; then
        # Delete only the file this login creates, not a user's normal Docker config.
        rm -f -- "$registry_config_dir/config.json"
        rmdir -- "$registry_config_dir" 2>/dev/null || true
    fi
}
