# go_router_patched

A **predictive-back-patched** local fork of [go_router](https://pub.dev/packages/go_router) v17.3.0.

## Purpose

GoRouter's `StatefulShellRoute.indexedStack` has Android predictive back gesture
bugs not fixed upstream:

1. **Back from non-root tab exits app** instead of oscillating to Home
   (PR [#11432](https://github.com/flutter/packages/pull/11432), closed without merge by author)

2. **Predictive back pops routes from ALL branch navigators** simultaneously,
   including inactive tabs
   (PR [#11910](https://github.com/flutter/packages/pull/11910), open, unreviewed)

The framework-level fix (PR [#152330](https://github.com/flutter/flutter/pull/152330))
is stalled in draft.

## What this patch does

### Fix 1: Shell PopScope — REMOVED

The original patch from PR #11432 wrapped `StatefulNavigationShellState.build()`
with a shell-level `PopScope`. This was removed because it is handled at the
app level when needed (e.g. in `AppShell`).

### Fix 2: Per-branch PopScope — REMOVED

The original patch from PR #11910 wrapped each branch navigator in
`_BranchNavigatorProxy` with `PopScope(canPop: isActive)`.

**This was removed because it caused critical bugs.** The `PopScope` sat
*outside* the branch `Navigator`, so it registered `PopEntry` objects on the
shell route's `ModalRoute` (root navigator), not on the branch's own
`ModalRoute`. With 3 inactive branches each adding `PopEntry(canPop: false)`,
the shell route's `popDisposition` became `doNotPop`, causing:

- Shell tabs: predictive back disappears (back events swallowed by
  `Navigator.maybePop` dispatching to empty callbacks)
- Root-level routes: wrong animation direction (system animation instead
  of `PredictiveBackPageTransitionsBuilder`)
- State corruption after warm restart or navigation to root-level routes

This is safe to remove for Aetherfin because all sub-routes use
`parentNavigatorKey: _rootKey` (pushed on the root navigator). Branch
navigators always have exactly 1 route and can never be popped.

## Upstream

- **Package:** https://pub.dev/packages/go_router
- **Version:** 17.3.0
- **Source:** https://github.com/flutter/packages

## Do Not Use Directly

This is an **internal dependency** of Aetherfin. Do not publish or use separately.
When GoRouter merges these fixes upstream, remove this patch and revert to the pub.dev version.
