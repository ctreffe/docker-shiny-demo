#!/usr/bin/env bash
# Copy new GitHub commits to GitLab without creating merge commits or force-pushing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ "${SYNC_ENABLED:-false}" == true ]] || fail "Synchronization is not enabled."
require_variables GITHUB_REPO_URL GITHUB_BRANCH GITLAB_SYNC_TOKEN CI_PROJECT_URL CI_DEFAULT_BRANCH
[[ "${CI_COMMIT_BRANCH:-}" == "$CI_DEFAULT_BRANCH" && "${CI_COMMIT_REF_PROTECTED:-false}" == true ]] ||
    fail "Start synchronization on the protected default branch."
case "${CI_PIPELINE_SOURCE:-}" in
    web|schedule) ;;
    *) fail "Use a manually started or scheduled synchronization pipeline." ;;
esac

# Only public HTTPS GitHub repositories are supported by this teaching example.
# This also prevents a variable from supplying another Git transport or local path.
[[ "$GITHUB_REPO_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]] ||
    fail "Use a public https://github.com/OWNER/REPOSITORY.git URL."
[[ "$CI_PROJECT_URL" == https://* && "$CI_PROJECT_URL" != *"@"* ]] || fail "Invalid GitLab project URL."
git check-ref-format "refs/heads/$GITHUB_BRANCH"
git check-ref-format "refs/heads/$CI_DEFAULT_BRANCH"

work="$(mktemp -d)"
cleanup() {
    # This job owns this temporary directory. The normal runner checkout is never
    # reset, merged or rewritten; GitLab changes are made only by the final push.
    rm -rf -- "$work"
}
trap cleanup EXIT

# Supply the token when Git asks for a password, rather than embedding it in a
# remote URL, command argument or repository configuration.
cat > "$work/askpass.sh" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
    *Username*) printf '%s\n' 'oauth2' ;;
    *Password*) printf '%s\n' "$GITLAB_SYNC_TOKEN" ;;
    *) exit 1 ;;
esac
ASKPASS
chmod 700 "$work/askpass.sh"
export GIT_ASKPASS="$work/askpass.sh" GIT_TERMINAL_PROMPT=0 LC_ALL=C
git init --quiet "$work/repository"
cd "$work/repository"
git -c credential.helper= fetch --quiet "$CI_PROJECT_URL.git" \
    "refs/heads/$CI_DEFAULT_BRANCH:refs/remotes/gitlab/source"
# The upstream fetch does not need or receive GitLab's authentication helper.
GIT_ASKPASS= GITLAB_SYNC_TOKEN= git -c credential.helper= fetch --quiet "$GITHUB_REPO_URL" \
    "refs/heads/$GITHUB_BRANCH:refs/remotes/github/source"

gitlab_sha="$(git rev-parse refs/remotes/gitlab/source)"
github_sha="$(git rev-parse refs/remotes/github/source)"
if [[ "$gitlab_sha" == "$github_sha" ]]; then
    printf 'GitLab already matches GitHub at %s.\n' "$github_sha"
    exit 0
fi

# A fast-forward adds commits without discarding any existing GitLab commit.
# Local GitLab edits or rewritten GitHub history require a maintainer decision.
git merge-base --is-ancestor "$gitlab_sha" "$github_sha" ||
    fail "The histories diverged. No update was pushed; resolve this with the hosting admins."

# No --force or mirror push: a concurrent GitLab change also makes this push fail.
# A write_repository access token triggers a fresh push pipeline for the imported
# commit. CI_JOB_TOKEN is intentionally not used, because its pushes do not do that.
git -c credential.helper= push "$CI_PROJECT_URL.git" \
    "$github_sha:refs/heads/$CI_DEFAULT_BRANCH"
printf 'GitLab updated to GitHub commit %s. Follow the new push pipeline in GitLab.\n' "$github_sha"
