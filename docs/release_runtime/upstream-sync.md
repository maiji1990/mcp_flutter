# Fork and upstream sync

This repository is a fork of `Arenukvern/mcp_flutter`. The fork's value is the
android-release runtime patch; everything else should keep flowing from
upstream.

## Hard rule: never open a pull request against upstream

**No PR, no patch submission, no issue-with-patch to
`Arenukvern/mcp_flutter` — ever.** The release runtime is fork-only product
work (embedded HTTP server, consent model, device policy). It is not an upstream
contribution, and offering it upstream would put the fork's security posture
under someone else's review cadence while it is still moving.

This applies to every agent and human working in this repository:

- push only to `origin` (the fork);
- pull from `upstream` read-only; `origin/main` is the product mainline and
  carries the fork's work, so upstream arrives by merge (see below);
- if a piece is genuinely upstream-shaped (for example a generic semantics or
  gesture interface), stop and ask the repository owner first. Do not open the
  PR yourself, and do not "prepare" one by pushing a branch to upstream.

There is no exception for docs, CI, or "tiny" fixes.

## Branch model

```
origin/main                 product mainline — carries the fork's work
upstream/main               Arenukvern/mcp_flutter (read-only source)
feat/android-release-mcp    the patch branch, merged into main at PR-06
```

`main` is **no longer a fast-forward mirror** of upstream: PR-01…PR-06 landed on
it as a `--no-ff` merge, so upstream can only arrive by an explicit merge (see
below). That is a deliberate trade — one mainline, one deployable branch — but
it means a `--ff-only` sync now fails on purpose.

If a clean mirror is ever wanted again, the shape to use is:

```bash
git branch release/main main            # keep the product branch
git switch main
git reset --hard upstream/main          # main back to a pure mirror
git push --force-with-lease origin main
```

## Syncing upstream

```bash
git fetch upstream --tags
git switch main
git merge upstream/main                 # not --ff-only: main has fork commits
# resolve conflicts where upstream touched the same files (it should not, in
# practice: the fork adds packages/ and docs/ paths upstream does not have)
dart test packages/release_runtime
flutter test packages/release_runtime_flutter
git push origin main
```

Then bring `feat/android-release-mcp` up to date:

```bash
git switch feat/android-release-mcp
git rebase main
git push --force-with-lease origin feat/android-release-mcp
```

`--force-with-lease` is only acceptable while the feature branch is single-owner.
Once others branch from it, merge `main` into it instead of rebasing.

## Baseline

The patch is written against `a58f120f` (2026-10-17), where `mcp_toolkit` and
the server are at `7.0.1`. Re-verify the baseline on every PR: upstream bumps
its SDK floor (3.13 here) and dependency floors, and the release runtime is a
workspace member, so its `resolution: workspace` participates in the root
resolution.

## Rules for the patch

- Do not modify existing debug behaviour or public `mcp_toolkit` /
  `mcp_server_dart` APIs.
- Do not remove `assert` or `kReleaseMode` guards to make release work; add a
  separate path instead.
- Reuse the existing semantics and gesture services rather than forking a second
  UI-tree implementation.
- No Dart eval, hot reload, arbitrary file IO, or shell in release tools.
- Every PR ships tests and states what was actually run.
