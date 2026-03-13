# GitHub Actions and CI/CD Inventory

This file is a fork-friendly briefing for the CI/CD automation currently present in this repository.
It focuses on two questions:

1. **What automation exists here today?**
2. **Which parts are likely worth keeping, reviewing, or disabling in a private customization fork?**

> This inventory is based on the files currently present in this repository, not on the upstream n8n workflow catalog.

## Quick recommendations for a private fork

If this fork is mainly for your own custom deployment work, the first candidates to review or disable are:

- scheduled cleanup and nightly workflows in `.github/workflows/util-*.yml` and `test-workflows-nightly.yml`
- release-automation workflows in `.github/workflows/release-*.yml` and `create-patch-release-branch.yml`
- dependency-bot configuration in `.github/dependabot.yml` and `renovate.json` if you do not want automated update PRs
- telemetry helpers in `.github/CI-TELEMETRY.md`, `.github/scripts/send-build-stats.mjs`, and `.github/scripts/send-docker-stats.mjs` if you do not have the required secrets or webhook endpoints

The workflows that are usually still valuable in a private fork are:

- `test-linting-reusable.yml`
- `test-db-reusable.yml`
- `test-e2e-reusable.yml`
- `test-e2e-docker-pull-reusable.yml`
- `test-e2e-helm.yml` if you deploy with Helm
- `sec-ci-reusable.yml`
- `codeql.yml` if you want GitHub security scanning
- `ci-check-pr-title.yml` and `ci-restrict-private-merges.yml` only if you still use PR-based collaboration

## GitHub Actions workflows

### CI and policy workflows

| File | Trigger(s) | Purpose | Private-fork recommendation |
| --- | --- | --- | --- |
| `.github/workflows/ci-check-pr-title.yml` | `pull_request_target` | Enforces Angular-style PR titles using `.github/pull_request_title_conventions.md`. | Keep if you use PRs; disable if you mostly commit directly. |
| `.github/workflows/ci-check-eligibility-reusable.yml` | `workflow_call` | Reusable gate that decides whether downstream CI should run. | Keep if other workflows call it. |
| `.github/workflows/ci-restrict-private-merges.yml` | `pull_request` | Blocks merge combinations that are unsafe for this branch strategy. | Keep if you still use release/private branches; otherwise review. |

### Test workflows

| File | Trigger(s) | Purpose | Private-fork recommendation |
| --- | --- | --- | --- |
| `.github/workflows/test-linting-reusable.yml` | `workflow_call` | Runs lint-style validation for code and workflow files. | Keep. |
| `.github/workflows/test-db-reusable.yml` | `workflow_call` | Runs database integration coverage. | Keep if you change backend or persistence code. |
| `.github/workflows/test-e2e-reusable.yml` | `workflow_call` | Main reusable end-to-end test workflow. | Keep. |
| `.github/workflows/test-e2e-docker-pull-reusable.yml` | `workflow_call`, `workflow_dispatch` | Validates a Docker image by pulling/running it in E2E tests. | Keep if Docker images are part of your delivery path. |
| `.github/workflows/test-e2e-performance-reusable.yml` | `workflow_call`, `workflow_dispatch`, `schedule`, `pull_request` | Performance-oriented E2E test workflow. | Review; often optional for a private fork. |
| `.github/workflows/test-e2e-helm.yml` | `pull_request`, `workflow_dispatch` | Helm-specific E2E coverage. | Keep only if you deploy via Helm. |
| `.github/workflows/test-bench-reusable.yml` | `workflow_call`, `workflow_dispatch` | Benchmark workflow for performance tracking. | Usually optional; disable if you do not track benchmark regressions. |
| `.github/workflows/test-evals-ai.yml` | `push`, `workflow_dispatch` | Runs AI evaluation coverage. | Keep only if your fork uses the AI evaluation surface. |
| `.github/workflows/test-evals-ai-release.yml` | `release` (`published`) | Runs AI evaluation checks when a GitHub release is published. | Usually disable in a private fork unless you publish release artifacts. |
| `.github/workflows/test-workflows-nightly.yml` | `schedule`, `workflow_dispatch` | Nightly test sweep for workflows. | Common housekeeping candidate to disable. |
| `.github/workflows/test-workflows-pr-comment.yml` | `issue_comment` | Lets maintainers trigger workflow tests from a PR comment. | Keep only if you rely on PR comment commands. |

### Security workflows

| File | Trigger(s) | Purpose | Private-fork recommendation |
| --- | --- | --- | --- |
| `.github/workflows/sec-ci-reusable.yml` | `workflow_call` | Shared security checks used by other CI entry points. | Keep. |
| `.github/workflows/sec-poutine-reusable.yml` | `workflow_dispatch`, `workflow_call` | Runs Poutine supply-chain checks using `.poutine.yml` and `.github/poutine-rules/`. | Keep if you want Actions supply-chain coverage. |
| `.github/workflows/codeql.yml` | `push`, `pull_request`, `schedule`, `workflow_dispatch` | GitHub CodeQL analysis for JavaScript, TypeScript, Python, and Actions. | Keep unless you have a replacement security scanner. |

### Release and maintenance workflows

| File | Trigger(s) | Purpose | Private-fork recommendation |
| --- | --- | --- | --- |
| `.github/workflows/release-create-minor-pr.yml` | `workflow_dispatch` | Prepares a minor-release PR, including version/changelog automation. | Usually disable in a private fork. |
| `.github/workflows/release-publish-post-release.yml` | `workflow_call` | Handles post-release bookkeeping after a publish flow completes. | Usually disable unless you run the upstream-style release process. |
| `.github/workflows/release-standalone-package.yml` | `workflow_dispatch` | Publishes standalone packages. | Usually disable unless you publish packages from this fork. |
| `.github/workflows/create-patch-release-branch.yml` | `workflow_dispatch` | Creates a patch release branch for hotfix work. | Review or disable if you do not maintain release branches. |
| `.github/workflows/util-determine-current-version.yml` | `workflow_dispatch`, `workflow_call` | Calculates current version information for release automation. | Disable if release automation is disabled. |
| `.github/workflows/util-ensure-release-candidate-branches.yml` | `workflow_dispatch`, `workflow_call` | Creates or verifies release-candidate branches. | Disable if you do not use release-candidate branches. |
| `.github/workflows/util-cleanup-pr-images.yml` | `schedule` | Deletes stale CI Docker images from GHCR. | Common housekeeping candidate to disable. |
| `.github/workflows/util-data-tooling.yml` | `workflow_dispatch` | Manual data import/export tooling workflow. | Keep only if you use this maintenance tool. |

## Custom composite actions

These are local GitHub Actions building blocks used by the workflow files above.

| File | Purpose | Notes |
| --- | --- | --- |
| `.github/actions/setup-nodejs/action.yml` | Standardized Node/pnpm/turbo setup for workflows. | Central place for cache, Node, and dependency bootstrap behavior. |
| `.github/actions/docker-registry-login/action.yml` | Shared login step for container registries. | Only needed if workflows push or pull protected images. |
| `.github/actions/ci-filter/action.yml` | Shared filtering logic to skip unnecessary CI work. | Useful even in a private fork if CI cost matters. |

## Other CI/CD-related files

### GitHub automation metadata

| File | Purpose | Private-fork note |
| --- | --- | --- |
| `.github/actionlint.yml` | Configures `actionlint` for workflow validation. | Keep if you edit workflow files. |
| `.github/dependabot.yml` | Enables daily dependency update PRs for npm, GitHub Actions, and Docker. | Disable if you prefer manual dependency updates. |
| `.github/CODEOWNERS` | Requests reviewers for owned paths. | Review if team ownership changed after the fork. |
| `.github/pull_request_template.md` | Default PR template. | Keep if you still use PRs. |
| `.github/pull_request_title_conventions.md` | Title rules used by `ci-check-pr-title.yml`. | Keep only with PR-title enforcement. |
| `.github/ISSUE_TEMPLATE/config.yml` | Directs issue reporters to the right destinations. | Update links for your fork if you keep GitHub Issues open. |
| `.github/ISSUE_TEMPLATE/01-bug.yml` | Bug-report form. | Optional in a private fork. |
| `.github/docker-compose.yml` | Service stack used for local or CI-style validation. | Keep if you run repo tests locally or in containers. |
| `.github/test-metrics/playwright.json` | Baseline metrics for Playwright-related measurements. | Only relevant if you keep Playwright performance tracking. |
| `.github/CI-TELEMETRY.md` | Documents telemetry emitted from CI workflows. | Review carefully; it assumes external webhook infrastructure and secrets. |

### Security and dependency automation

| File | Purpose | Private-fork note |
| --- | --- | --- |
| `.poutine.yml` | Poutine scan configuration and approved exceptions for Actions security checks. | Keep if `sec-poutine-reusable.yml` stays enabled. |
| `.github/poutine-rules/unpinned_action.rego` | Custom Poutine policy rules. | Keep with Poutine; otherwise optional. |
| `renovate.json` | Renovate dependency update policy and grouping rules. | Disable if you do not use Renovate. |
| `codecov.yml` | Codecov upload/check behavior and component grouping. | Keep only if you upload coverage to Codecov. |

### Automation scripts used by workflows

The workflow directory depends heavily on scripts in `.github/scripts/`.
These are part of the CI/CD system even though they are not workflow files themselves.

| File group | Purpose |
| --- | --- |
| `.github/scripts/bump-versions.mjs`, `.github/scripts/update-changelog.mjs`, `.github/scripts/determine-version-info.mjs`, `.github/scripts/get-release-versions.mjs`, `.github/scripts/move-track-tag.mjs`, `.github/scripts/plan-release.mjs`, `.github/scripts/cleanup-release-branch.mjs`, `.github/scripts/ensure-release-candidate-branches.mjs` | Release orchestration and branch/tag/version management. |
| `.github/scripts/cleanup-ghcr-images.mjs` | Housekeeping for container images stored in GHCR. |
| `.github/scripts/send-build-stats.mjs`, `.github/scripts/send-docker-stats.mjs` | CI telemetry emitters that assume external webhook endpoints. |
| `.github/scripts/detect-new-packages.mjs`, `.github/scripts/ensure-provenance-fields.mjs`, `.github/scripts/trim-fe-packageJson.js` | Packaging and publish-time preparation. |
| `.github/scripts/validate-docs-links.js` | Repo automation for documentation link validation. |
| `.github/scripts/docker/*.mjs` | Docker tag and manifest helpers used by release/build flows. |
| `.github/scripts/claude-task/*.mjs` and `.github/claude-templates/*.md` | AI-assisted maintenance automation. Review closely; many forks do not need this. |

### Root-level CI/CD files outside `.github/`

| File | Purpose | Private-fork note |
| --- | --- | --- |
| `/home/runner/work/n8n/n8n/package.json` | Defines root build, lint, test, Docker, and typecheck commands. | Keep. This is the main local CI entry point. |
| `/home/runner/work/n8n/n8n/lefthook.yml` | Pre-commit automation for formatting, actionlint, and workspace checks. | Keep if you want local guardrails. |
| `/home/runner/work/n8n/n8n/docker-compose.yml` | Local service orchestration used for development and testing. | Keep if your deployment or tests still use it. |
| `/home/runner/work/n8n/n8n/Dockerfile` and `/home/runner/work/n8n/n8n/docker/images/**/Dockerfile` | Container build definitions used by Docker-based delivery and testing. | Keep if Docker remains your runtime path. |

## Practical cleanup order for this fork

If you want to reduce noise without breaking useful validation, a conservative sequence is:

1. Disable the scheduled housekeeping workflows:
   - `.github/workflows/util-cleanup-pr-images.yml`
   - `.github/workflows/test-workflows-nightly.yml`
   - optionally the scheduled path inside `.github/workflows/test-e2e-performance-reusable.yml`
2. Disable release-only workflows if you are not publishing from this fork:
   - `.github/workflows/release-create-minor-pr.yml`
   - `.github/workflows/release-publish-post-release.yml`
   - `.github/workflows/release-standalone-package.yml`
   - `.github/workflows/create-patch-release-branch.yml`
   - `.github/workflows/util-determine-current-version.yml`
   - `.github/workflows/util-ensure-release-candidate-branches.yml`
3. Disable dependency bots you do not plan to use:
   - `.github/dependabot.yml`
   - `renovate.json`
4. Keep at least one security layer and one validation path:
   - security: `codeql.yml` and/or `sec-poutine-reusable.yml`
   - validation: `test-linting-reusable.yml`, `test-db-reusable.yml`, `test-e2e-reusable.yml`

## Incomplete or upstream-dependent workflow references

Some workflow files in this fork still reference reusable workflows that are **not currently present** under `.github/workflows/`.
That is a strong sign that parts of the original upstream automation were removed, renamed, or never copied into this fork.

- `.github/workflows/test-evals-ai.yml` and `.github/workflows/test-evals-ai-release.yml` reference `test-evals-ai-reusable.yml`
- `.github/workflows/release-publish-post-release.yml` references `release-push-to-channel.yml`
- `.github/workflows/release-create-minor-pr.yml` references `release-create-pr.yml`
- `.github/workflows/test-workflows-nightly.yml` and `.github/workflows/test-workflows-pr-comment.yml` reference `test-workflows-callable.yml`

For a private fork, this usually means one of two things:

1. you should restore the missing reusable workflows before relying on those entry points, or
2. you should disable the now-incomplete workflows to reduce confusion and failed runs

## Validation and maintenance notes

- `package.json` shows the repo expects `pnpm`-based commands such as `build`, `typecheck`, `lint`, and `test`.
- `lefthook.yml` shows workflow edits are expected to pass `actionlint` before commit.
- `codecov.yml`, `renovate.json`, `.github/dependabot.yml`, and `.github/CI-TELEMETRY.md` are all optional integrations rather than core runtime requirements.
- For a private fork, the lowest-risk simplification is usually to keep validation and security checks, while disabling scheduled cleanup, release publishing, and bot-driven maintenance you do not actively use.
