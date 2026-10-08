import Cocoa

/// A settings page's searchable content, split into a fixed base captured during its build-time
/// `SettingsSearchIndex.indexed { }` scope and a replaceable dynamic part for rebuilt sidebar rows.
/// The index remains available even while the page is detached from the document view.
///
/// ControlsTab's shortcut rows are refreshed outside the build-time scope by preference changes,
/// the +/- buttons, and input-source changes. Their inline registration has no active builder,
/// so retaining build-time row targets would leave removed labels in the index. Sections with
/// such rows skip them in the build-time walk and replace their dynamic content after each rebuild.
final class SettingsSectionSearchContent {
    private let baseStrings: [String]
    private let baseTargets: [SettingsSearchHighlightTarget]
    private var dynamicStrings: [String] = []
    private var dynamicTargets: [SettingsSearchHighlightTarget] = []

    init(strings: [String] = [], targets: [SettingsSearchHighlightTarget] = []) {
        baseStrings = strings
        baseTargets = targets
    }

    /// Replace the dynamic part wholesale. Called after a section rebuilds its sidebar rows, with
    /// the strings + highlight targets freshly registered from the *current* rows. Replacing (not
    /// appending) is the whole point: targets for removed rows are dropped, so no stale highlight
    /// targets accumulate and `searchableStrings` never reports rows that no longer exist.
    func setDynamic(strings: [String], targets: [SettingsSearchHighlightTarget]) {
        dynamicStrings = strings
        dynamicTargets = targets
    }

    var searchableStrings: [String] { baseStrings + dynamicStrings }
    var highlightTargets: [SettingsSearchHighlightTarget] { baseTargets + dynamicTargets }

    /// True when the query is empty or any base/dynamic string or highlight target matches it.
    /// Determines whether this page remains available in the filtered sidebar, not whether it is mounted.
    func matches(_ query: String) -> Bool {
        if SettingsSearch.isQueryEmpty(query) { return true }
        if searchableStrings.contains(where: { SettingsSearch.match(query, in: $0) != nil }) {
            return true
        }
        return highlightTargets.contains { $0.hasMatch(query) }
    }

    func highlightMatches(_ query: String) {
        highlightTargets.forEach { $0.updateHighlight(query) }
    }

    func clearHighlights() {
        highlightTargets.forEach { $0.clear() }
    }
}
