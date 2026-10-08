# SettingsSectionSearchContent: Specs

## Summary

Holds a settings page's searchable content in two parts:

- **base**: captured once during the page's build-time `SettingsSearchIndex.indexed { }` scope
  (page title, dropdowns, buttons, static labels), retained while the page is detached.
- **dynamic**: shortcut rows republished wholesale via `setDynamic` after +/- actions, recorder edits,
  and input-source changes. The build-time walk skips those rows so only the dynamic content tracks them.

Dynamic rows register outside the build-time scope, where no builder is active. Republishing the
current rows replaces removed labels and keeps newly added rows searchable and highlightable.

## Behavior & edge cases

- `matches` is true for an empty query, or when any base or dynamic string/target matches, regardless of
  whether the page is mounted. An empty query keeps every destination available in the sidebar.
- `setDynamic` **replaces** the dynamic part: targets for removed rows are dropped (no stale
  targets), and newly-added rows become searchable immediately.
- `highlightMatches` / `clearHighlights` drive both base and dynamic targets.
- A section with no dynamic content behaves exactly like its base.

## Page presentation

- The sidebar has four destinations, in order: Appearance, Controls, General, and Exceptions.
  A newly constructed window selects Appearance. Only the selected page is mounted in the
  document view. Scrolling never selects another destination.
- All four pages retain their controls and indexes for the window's lifetime. Switching pages
  commits any field editor owned by the departing page without taking focus from the search field.
- Each page remembers its own scroll offset. Navigation restores that offset after layout and
  clamps it to the current content height. Resizing or changing the active page's layout also
  clamps its offset; short pages and the no-results state do not retain a tall page's scroll range.
- Search filters sidebar destinations globally, including controls in detached pages and metadata
  for unopened customization sheets. If the selected destination still matches, it stays selected;
  otherwise the first matching destination is selected. Other matches are not mounted simultaneously.
- A query with no matches detaches the active page and displays a localized message suggesting a
  different search. Clearing the query makes all destinations available and selects Appearance.
- Explicit navigation keeps a matching query. If the destination does not match, it clears the query
  and mounts that destination directly.
- Highlights apply to the selected page and any open settings sheets. A departing page's highlights
  are cleared. Dynamic shortcut content is republished immediately after each row refresh.
- Closing the window defers tab cleanup until AppKit's close callback finishes. Cleanup does not
  tear down a window reopened before that deferred block runs, or a replacement window.

## Unit test scenarios

Mirrors `SettingsSectionSearchContentTests.swift` 1:1.

- **testEmptyQueryAlwaysMatches**: an empty or whitespace query keeps the page available.
- **testBaseStringIsSearchable**: a base string drives a match.
- **testDynamicStringIsSearchable**: a string published via `setDynamic` drives a match.
- **testDynamicTargetReportsAndHighlightsMatch**: a dynamic target both reports and highlights a match.
- **testSetDynamicReplacesAndDropsStaleTargets**: republishing current rows replaces the dynamic part;
  the new rows match and highlight, and the previous rows disappear.
- **testSetDynamicReplaceDoesNotAccumulate**: repeated replacement leaves only the latest dynamic content.
- **testClearHighlightsClearsDynamicTargets**: `clearHighlights` reverts dynamic targets too.

## App-level integration scenarios

These exercise the real SettingsWindow, which is not compiled into the unit test target.

- Visit all four destinations, scroll each, and return. Confirm one mounted page, stable sidebar
  selection during scrolling, restored page-local offsets, and clamping after resize.
- Search a term present on multiple pages. Switch between matching destinations and confirm only
  the selected page is shown. Try a nonmatching query, then clear it and recover the four destinations.
- Add, rename, and remove shortcut rows while searching. Confirm the current title and summary are
  searchable, removed content disappears, and matching row highlights remain current.
- Open the customization, animation, and active-shortcuts sheets from their matching search results.
  Confirm both sheet and popover highlights follow the query without replacing the selected page.
- Follow an Appearance override indicator into a shortcut's Appearance pane, including with a query
  that excludes Controls. Confirm explicit navigation mounts Controls and preserves the shortcut choice.
- Edit an exception bundle ID or title pattern, then change pages and return. Confirm the value is
  committed without resetting preferences.
- Close and immediately reopen the same window before deferred cleanup. Then close, let cleanup
  complete, and reopen a new window. Confirm controls and sheets remain usable in both cases.
