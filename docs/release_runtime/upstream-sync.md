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
- pull from `upstream` read-only, to keep `main` a mirror;
- if a piece is genuinely upstream-shaped (for example a generic semantics or
  gesture interface), stop and ask the repository owner first. Do not open the
  PR yourself, and do not "prepare" one by pushing a branch to upstream.

There is no exception for docs, CI, or "tiny" fixes.

## Branch model

```
origin/main                 mirror of upstream/main — never carries fork work
upstream/main               Arenukvern/mcp_flutter
feat/android-release-mcp    the patch (PR-01..PR-06)
release/main                optional product branch; takes feature PRs
```

## First-time setup

```bash
git remote add upstream https://github.com/Arenukvern/mcp_flutter.git
git fetch upstream --tags
git switch main
git merge --ff-only upstream/main
git push origin main

git switch -c feat/android-release-mcp
```

## Syncing upstream

```bash
git fetch upstream --tags
git switch main
git merge --ff-only upstream/main
git push origin main

git switch feat/android-release-mcp
git rebase upstream/main
# resolve, run tests, then:
git push --force-with-lease origin feat/android-release-mcp
```

`--force-with-lease` is only acceptable while the feature branch is single-owner.
A shared `release/main` takes merges from `feat/android-release-mcp` instead of
being rebased.

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
