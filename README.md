# docker-shiny-demo

[Deutsche Fassung](README.de.md)

A minimal R/Shiny application that demonstrates Docker containerization, import
from GitHub into GitLab, and CI/CD deployment through a managed hosting platform.

## Project and goal

The goal is to make the whole path from application source to a running container
understandable. You can run the demo locally, change its greeting through an
environment variable, and follow the same application into a GitLab build and
deployment workflow. The code and configuration files contain English comments
that explain the steps and their purpose.

GitHub is the source of truth for the maintained files. The hosting admins import
the public repository into the **Gemi** group (namespace `gemi`) on
`gitlab.gwdg.de`. Only the hosting admins can create projects in this group.
An optional GitLab job later copies new GitHub commits into the GitLab repository.
The application does not need GitHub Actions or a GitHub container registry.

The demo has one interactive web page. A slider selects a number from 1 to 10;
the server calculates its square. The page also displays a configurable greeting.
The health check requests this page at `/`; there is no separate `/health`
endpoint. The demo has no login, database or persistent user data. Hosting admins
configure the public hostname, reverse proxy, TLS and any required access
restrictions separately.

GitHub is optional for your own application. The admins can instead create an
empty project in **Gemi**, and you can maintain the same files directly in GitLab.
Keep synchronization disabled in that case and push release commits directly to
GitLab. This example documents the GitHub path alongside the shared hosting steps.

## Files

| File | Purpose |
|---|---|
| `app.R` | Shiny interface, escaped greeting and reactive square calculation |
| `requirements.R` | Direct R package requirements, installed/checked during the image build |
| `shiny-server.conf` | One application on port 3838, with writable runtime paths in `/tmp` |
| `Dockerfile` | Rocker image with Shiny Server, a non-root user and an HTTP health check |
| `compose.yaml` | Local build and access through the computer's loopback interface |
| `compose.hosting.yaml` | Hosting configuration with the external `dockernet` network |
| `.env.example` | Harmless local configuration template |
| `.gitignore`, `.dockerignore` | Keep local settings and unnecessary files out of Git and the image |
| `.gitattributes` | Preserve Linux line endings in scripts edited on Windows |
| `.gitlab-ci.yml` | Tests, optional synchronization, image build and release rules |
| `scripts/common.sh` | Shared variable checks and temporary registry login |
| `scripts/build.sh` | Build, start-test and publish an image; record its registry digest |
| `scripts/deploy.sh` | Validate the target, deploy the recorded image and verify the backend |
| `scripts/sync.sh` | Copy GitHub commits to GitLab only when a fast-forward is possible |
| `scripts/start.sh` | Prepare disposable configuration and start Shiny Server |
| `scripts/restore-environment.R` | Restore the public greeting in each R worker's startup profile |
| `scripts/probe.R` | Check the app's HTTP response, optionally including the expected greeting |
| `scripts/test.sh` | Run the app, CI-script and shell syntax checks |
| `tests/` | App behavior and CI-script tests without real Git pushes or deployments |
| `TROUBLESHOOTING.md` | Confirmed Shiny runtime and local test issues, with their fixes |
| `LICENSE` | MIT license |

## Run locally with Docker

You need Docker Desktop using Linux containers, or Docker Engine on Linux, and
Docker Compose v2 supporting `up --wait --wait-timeout` and `config --format json`.
Start Docker before running the commands. Run them from this repository's folder.

1. Copy the example settings. In Windows PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

   On Linux or macOS:

   ```sh
   cp .env.example .env
   ```

2. Open `.env` in a text editor. Keep the default greeting or change
   `GREETING_TEXT`. `APP_PORT=3838` selects the local port.

3. Build and start the container:

   ```sh
   docker compose up --build --detach --wait --wait-timeout 90
   ```

4. Open [the local web page](http://localhost:3838). The page shows the greeting
   and initially `4 squared is 16`. Move the slider to 7 and check that the result
   becomes `7 squared is 49`. If you changed `APP_PORT`, use that port in the URL.
   You can also check the status and logs:

   ```sh
   docker compose ps
   docker compose logs --tail 100 app
   ```

5. After changing `GREETING_TEXT`, recreate the container:

   ```sh
   docker compose up --detach --force-recreate --wait --wait-timeout 90
   ```

   Refresh the page to see the new text. Changing `.env` does not require an image
   rebuild. Changes to `app.R`, the server configuration, scripts or dependencies
   do require a rebuild.

6. When finished, stop and remove this demo's local container and network:

   ```sh
   docker compose down
   ```

The local port is bound to `127.0.0.1`, so this command does not publish the demo
to other computers. The real `.env` is ignored by Git and excluded from the image.

The image uses `rocker/shiny:4.6.1`. Shiny Server and its R workers run as the
`shiny` user with a read-only root filesystem. Temporary files, session logs and
bookmark directories live in a 256 MB `/tmp` tmpfs and disappear when the
container is removed. Server and application diagnostics are also available in
`docker compose logs`. This demo does not enable persistent bookmarking.

`requirements.R` lists direct packages; the base image already supplies Shiny.
It is not a package lock file. For an application with additional dependencies,
add them there and consider an `renv.lock` workflow. The versioned base-image tag
can still receive updates; the GitLab release records the digest of the final
built image.

## How the environment variable works

`.env.example` documents a safe value. Your local `.env` supplies values to Docker
Compose. The `environment` block in `compose.yaml` explicitly passes
`GREETING_TEXT` into the container. Shiny Server starts R workers with a reduced
environment, so `scripts/start.sh` saves only this public setting in a private
file in tmpfs. `scripts/restore-environment.R`, copied to
`/home/shiny/.Rprofile`, restores it in each worker. The app then reads it with
`Sys.getenv("GREETING_TEXT", unset = "Hello from the Shiny container!")`.

The temporary RDS file stores data rather than generated R code, preserving
quotes, dollar signs and newlines. It is recreated at every container start.
Do not replace this explicit setting with a dump of all CI variables.

On GitLab, a CI/CD variable supplies the hosting value instead. The deployment
script resolves `compose.hosting.yaml` and saves the runtime configuration on the
host. This saved configuration includes the greeting. Use only public text for
`GREETING_TEXT`; the web page displays it to every visitor. Real secrets belong
in separately reviewed secret configuration, never in this repository or image.

## Optional initial import from GitHub

Only the hosting admins can create or import projects in **Gemi** (namespace
`gemi`). As an application owner, request the import from them. If you are a
hosting admin, follow the steps below yourself. This example requests a public
GitLab project, just like the public GitHub source.

### Request the import

Send the hosting admins the following information and your GitLab username:

| Item | Value for this example |
|---|---|
| Public source repository | `https://github.com/ctreffe/docker-shiny-demo.git` |
| Source branch | `main`; agree the intended latest commit before importing |
| Destination instance | `https://gitlab.gwdg.de` |
| Destination group / namespace | **Gemi** / `gemi` |
| Project name and slug | `docker-shiny-demo` |
| Visibility | **Public** |

The source URL must point to the GitHub repository. The destination namespace
selects where GitLab creates the new project; it is not the source URL.

### Import steps for the hosting admins

1. Open [gitlab.gwdg.de](https://gitlab.gwdg.de) and sign in with your authorized
   account. Confirm that you may create projects in **Gemi** and that the target
   project name is available.
2. Open **Create new** (the plus menu) and select **New project/repository**.
   Select **Import project**, then **Repository by URL**. Labels and menu
   positions can differ with the installed GitLab version and interface language.
3. Enter `https://github.com/ctreffe/docker-shiny-demo.git` in **Git repository
   URL**. Leave source username and password/token fields empty: this repository
   is public, so its import does not need GitHub credentials.
4. Complete the destination fields as follows:

   | Field | Value |
   |---|---|
   | Project name | `docker-shiny-demo` |
   | Project URL / namespace | Select **Gemi** (`gemi`), not your personal namespace |
   | Project slug / path | `docker-shiny-demo` |
   | Visibility level | **Public** if available; otherwise agree an initial **Private** import |

   Check that the resulting destination path is `gemi/docker-shiny-demo`.
   If **Gemi** is missing, have the group permissions checked. If **Repository
   by URL** is missing, ask the GitLab instance admins whether this import source
   can be enabled. Resolve missing namespace or import permissions before
   creating the project. If **Public** is unavailable, an agreed initial
   **Private** import is possible; see the visibility follow-up below.
5. Select **Create project** and wait for the import to finish. The expected
   project address is `https://gitlab.gwdg.de/gemi/docker-shiny-demo`, provided
   that the agreed namespace and slug are used. This address is a destination
   example, not confirmation that the project already exists.
6. Open the repository on branch `main` and compare the latest commit's full SHA
   with GitHub. URL import copies the repository as it exists during the import;
   writing an intended SHA in the request does not pin it. If GitHub changed in
   the meantime, agree which revision should be accepted. Check that `app.R`,
   `Dockerfile`, `.env.example`, `.gitlab-ci.yml`, `scripts/` and both READMEs
   are present. Pipeline files and scripts are already included.
7. Grant the application owner the agreed project membership and send them the
   project URL. Review the imported CI code and make a suitable Linux
   Docker-executor runner available for `test-app`. For the first test, keep
   `HOSTING_ENABLED=false`, `SYNC_ENABLED=false` and `RUN_SYNC=false`; confirm
   that inherited group or project variables do not override these values.
8. Open **Build > Pipelines** and inspect any existing pipeline for that commit.
   If none exists, select **New pipeline** (called **Run pipeline** in some
   versions), choose `main`, keep `RUN_SYNC=false` and start the pipeline.
   With hosting and synchronization disabled, only `test-app` is selected.
   Open its log and verify that it passes. A pending job requires the admins
   to check runner availability; a completed import alone does not verify CI.

### If the project was initially imported as private

During the parallel Flask demo, **Public** was not offered during import on
`gitlab.gwdg.de`, so that project was initially created as **Private**. The reason
for the missing option has not yet been confirmed. The same restriction may
apply to this Shiny project. There is no need to repeat an import solely because
the visibility may change later.

Ask a group Owner to check the visibility of **Gemi** and any parent groups.
A project cannot be more public than its containing groups: private groups allow
only private projects, and internal groups do not allow public projects.
If public visibility is restricted by the GitLab instance, the GWDG instance
admins must resolve that restriction; a group Owner cannot override it.

Once the required group visibility and instance permissions allow it, a project
Owner can open **Settings > General > Visibility, project features, permissions**,
set **Project visibility** to **Public**, and save the change. Making the group
public does not automatically make its existing private projects public.

While the project remains private, authorized members can continue checking its
files and test pipeline. Public repository visibility is separate from the
application's eventual hostname and web access configuration.

### What the import accomplishes

The first import is performed by GitLab itself, not by a runner. It copies the
Git repository once, including its history, and does not establish continuous
synchronization or copy GitHub issues and pull requests. Hosting setup and
optional later synchronization are separate steps described below.

Application owners verify the imported revision and files after receiving access.
The hosting admins review the imported CI code before granting access to deployment
runners or credentials. A successful first test pipeline confirms the test job;
it does not deploy the application.

The procedure follows the [GitLab URL-import documentation](https://docs.gitlab.com/user/import/third_party_systems/repo_by_url/),
[project visibility rules](https://docs.gitlab.com/user/public_access/) and
[manual pipeline documentation](https://docs.gitlab.com/ci/pipelines/#run-a-pipeline-manually).
Import-option availability and the authenticated GWDG interface still need to be
confirmed by the hosting admins on the actual instance.

## Hosting setup by the admins

Before enabling hosting, confirm the runner executors, registry and permissions
on the actual GitLab instance. Test and sync jobs expect a suitable Linux
Docker-executor runner. Build and deploy jobs expect a Linux **shell-executor**
runner tagged with both `apps.psych` and `production`, with Bash, Git, `python3`,
Docker Engine, Docker Compose v2 and GNU `realpath` already available. These
jobs use that host's Docker daemon; a job's `image:` does not configure a shell
executor. The tag names alone do not establish these capabilities.

Enable the project's Container Registry and protect the default branch. Configure
who may change it or start its pipelines. Enable **Prevent outdated deployment
jobs** in the GitLab deployment settings. Configure the `production` environment
controls where the installed edition supports them. Choose a dedicated app
directory below the platform's existing deployment root and confirm that
`dockernet` exists. The deployment job creates missing app directories itself;
no manual directory creation is needed for each new application. The runner
must already be allowed to create directories under the chosen root and write
to an existing app directory. This is part of the shared platform setup.

Add the following variables under **Settings > CI/CD > Variables**. Hosting and
sync settings must be protected and available to their jobs. Use the **All**
environment scope for this example: build and sync jobs do not declare the
`production` environment. Do not override predefined `CI_*` variables or the
release artifact variables `APP_IMAGE`, `RELEASE_COMMIT`, `RELEASE_PIPELINE_ID`.

| Variable | Value or responsibility |
|---|---|
| `HOSTING_ENABLED` | `true` after the hosting setup has been reviewed; default is `false` |
| `GREETING_TEXT` | Public greeting, for example `Hello from GitLab!`; the app has a default |
| `DEPLOY_ROOT` | Existing, admin-approved root, for example `/opt/docker/apps`; never `/` |
| `DEPLOY_DIR` | App path strictly below the root, for example `/opt/docker/apps/docker-shiny-demo`; the job creates it if missing |
| `APP_CONTAINER_NAME` | Unique container name assigned by the admins, for example `docker-shiny-demo` |
| `APP_NETWORK_ALIAS` | Unique backend name on `dockernet`, for example `docker-shiny-demo`, assigned by the admins |
| `SYNC_ENABLED` | `true` only if later GitHub updates are wanted; default is `false` |
| `GITLAB_SYNC_TOKEN` | Masked, protected access token with `write_repository`, whose account may push to the protected default branch |

GitLab supplies `CI_REGISTRY`, `CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER` and
`CI_REGISTRY_PASSWORD` for registry access. The scripts keep the job's registry
login temporary. The admins configure the shared proxy to reach
`APP_NETWORK_ALIAS:3838`, and handle DNS, TLS and access restrictions separately.
No host port is published by the hosting Compose file. The reverse proxy must
support Shiny's interactive connections, including WebSocket upgrades.

For synchronization, prefer a project access token if the instance supports it;
otherwise use a dedicated personal access token with the stated scope and an
appropriate expiry. Do not use `CI_JOB_TOKEN` for this example's push: its pushes
do not trigger the follow-up pipeline. Keep application changes on GitHub.
GitLab-only commits would make the two histories diverge and stop synchronization.

## Optional later updates through a runner

After the admins enable synchronization and configure its token:

1. Review and push the intended changes to the default branch on GitHub.
2. In GitLab, open **Build > Pipelines** and start a new pipeline on the protected
   default branch. Set the pipeline variable `RUN_SYNC` to `true`.
3. The sync job fetches `GITHUB_REPO_URL` and `GITHUB_BRANCH` (this repository and
   `main` by default). If new commits extend GitLab's current history, it pushes
   them without a merge commit or force-push. If the histories match, it does
   nothing. If they diverge, it fails and the admins must resolve the difference.
4. A successful update starts a **new push pipeline** for the imported commit.
   Follow that pipeline for tests, build and any release. The sync pipeline itself
   does not build or deploy the old checkout.

An optional schedule can start the same sync job with `RUN_SYNC=true`. Agree this
separately with the admins. A newly synchronized tip commit containing `[deploy]`
can cause the follow-up pipeline to deploy when hosting is enabled. A schedule
does not bypass review or change the release rule.

The sync job follows one branch. It does not mirror tags, other branches, GitHub
issues, pull requests or deletions. If a push succeeded but the follow-up pipeline
failed to start, start a normal pipeline manually on the imported default-branch
commit, with `RUN_SYNC=false`; do not repeat an unrelated release commit.

## Build and release rule

Ordinary branch pipelines run the tests. With hosting enabled, protected
default-branch push or manually started pipelines also build and smoke-test an
image and publish it in the GitLab Container Registry. Deployment additionally
requires the exact substring **`[deploy]`** in that commit's message. The match is
case-sensitive. `deploy`, `[deployment]`, other branches, tags, merge-request
pipelines and the sync pipeline do not select the deployment job.

For a release, review the complete source, then push a default-branch commit with
a message such as `Release demo [deploy]` to GitHub and start the sync job. The
new GitLab pipeline tests and builds that imported revision before deployment.

The deployment consumes the build's immutable `@sha256:` image reference and
checks its commit and pipeline labels. It rejects an outdated branch head or an
older pipeline than the last successful deployment. The script validates the
resolved target path before writes, creates a missing app directory and starts
the image through Compose. It waits for the health check and verifies HTTP
access from `dockernet`. New directories are accessible only to the runner user
(mode `0700`); existing directories retain their permissions and contents.
The job never creates the platform root or changes ownership or permissions of
existing directories. If the runner lacks access, it fails with an explicit
message; a platform administrator then needs to correct the shared permissions.

Application owners can therefore deploy the container without a separate manual
app-directory step. Once it runs on the host, the hosting admins accept the
backend and configure public routing, DNS, TLS and any access restrictions.

After acceptance, `DEPLOY_DIR/compose.json` holds the resolved runtime settings;
`DEPLOY_DIR/release.txt` records pipeline ID, commit and image digest. App code is
inside the image, not mounted from the runner checkout. The script does not delete
host data or secrets. If startup or backend verification fails, the job fails and
retains the candidate configuration for diagnosis. The live container may already
have changed; there is no automatic rollback. The admins inspect the service
before retrying and manage any recovery explicitly.

The files are a teaching implementation. Import, runner compatibility, image
build, deployment, public routing and recovery must be verified on the actual
GWDG/hosting setup before treating it as a working production workflow.

## Tests and troubleshooting

GitLab runs four R behavior checks, ten Python script tests and shell syntax
checks. The R tests cover the default and environment greetings, HTML escaping
and reactive slider updates through `shiny::testServer`. HTTP probes check the
rendered page and its input; a healthy container alone does not prove that the
browser's interactive connection works. For acceptance, move the slider in a
browser and verify the updated result.

Run the same checks locally in the separate test image:

```sh
docker build --target tests --tag docker-shiny-demo:tests .
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,exec,nosuid,size=256m docker-shiny-demo:tests
```

The test image adds `testthat` and the test tools. The default runtime image does
not copy the tests or CI scripts. Only the test container's temporary directory
is executable: the fake Git program needs it. The app containers retain
`noexec` on `/tmp`.

The script tests use a fake Git executable and never push or create real
repositories. Deployment-directory tests run on Linux/POSIX with Bash and GNU
`realpath`; they exercise real creation and path boundaries in temporary folders.
Permission tests require an unprivileged user, as used in the local test image.
See [confirmed fixes](TROUBLESHOOTING.md) for the Shiny-specific runtime details.

| Symptom | What to check |
|---|---|
| Docker cannot connect | Start Docker Desktop and select Linux containers |
| Local port is already used | Change `APP_PORT` in `.env` and recreate the container |
| Greeting did not change | Recreate the container after changing `.env` |
| GitLab job remains pending | Confirm runner availability, executor, tags and protected-branch access |
| Only tests run | Hosting is disabled by default; admins must configure and enable it |
| Sync reports diverged histories | Preserve both sides and ask the admins; do not force-push |
| No deploy job appears | Check the exact marker, default/protected branch, hosting flag and pipeline source |
| Deployment fails | Read the job's error and logs; have the admins inspect the live service and candidate configuration |

## References and license

- [Rocker Shiny images](https://rocker-project.org/images/versioned/shiny.html)
- [Shiny Server configuration](https://docs.posit.co/shiny-server/)
- [Shiny Server R worker environment implementation](https://github.com/rstudio/shiny-server/blob/master/lib/worker/app-worker.js)
- [Shiny server-function testing](https://shiny.posit.co/r/reference/shiny/latest/testserver.html)
- [R startup profiles](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Startup.html)
- [Docker Compose environment interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)
- [GitLab import through a Git URL](https://docs.gitlab.com/user/import/third_party_systems/repo_by_url/)
- [GitLab CI/CD variables](https://docs.gitlab.com/ci/variables/)
- [GitLab job-token push behavior](https://docs.gitlab.com/ci/jobs/ci_job_token/#allow-git-push-requests-to-your-project-repository)
- [GitLab deployment safety](https://docs.gitlab.com/ci/environments/deployment_safety/)

This project is distributed under the [MIT license](LICENSE).
