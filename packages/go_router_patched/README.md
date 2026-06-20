# go_router_patched

A **predictive-back-patched** local fork of [go_router](https://pub.dev/packages/go_router) v17.3.0.

## Purpose

GoRouter's `StatefulShellRoute.indexedStack` has two Android predictive back gesture
bugs not fixed upstream:

1. **Back from non-root tab exits app** instead of oscillating to Home
   (PR [#11432](https://github.com/flutter/packages/pull/11432), closed without merge by author)

2. **Predictive back pops routes from ALL branch navigators** simultaneously,
   including inactive tabs
   (PR [#11910](https://github.com/flutter/packages/pull/11910), open, unreviewed)

The framework-level fix (PR [#152330](https://github.com/flutter/flutter/pull/152330))
is stalled in draft.

## What this patch does

### Fix 1: Shell PopScope (from PR #11432)

Wraps `StatefulNavigationShellState.build()` with `PopScope`:

- `canPop: currentIndex == 0` — only root branch allows app exit
- Non-root branches call `goBranch(0)` to oscillate back to Home

### Fix 2: Per-branch PopScope (from PR #11910)

Wraps each branch navigator in `_BranchNavigatorProxy` with `PopScope`:

- `canPop: isActive` — only the active branch handles system back
- Inactive branches are blocked from receiving back events

## Upstream

- **Package:** https://pub.dev/packages/go_router
- **Version:** 17.3.0
- **Source:** https://github.com/flutter/packages

## Do Not Use Directly

This is an **internal dependency** of Aetherfin. Do not publish or use separately.
When GoRouter merges these fixes upstream, remove this patch and revert to the pub.dev version.
