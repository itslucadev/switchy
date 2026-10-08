import Cocoa
import XCTest

/// Covers the per-page search store's fixed build-time content and replaceable dynamic content.
/// ControlsTab republishes shortcut rows after +/- actions, recorder edits, and input-source changes.
/// These tests ensure the index drops removed rows and searches the current rows independently
/// of which settings page is mounted. The full ControlsTab and SettingsWindow are not compiled
/// into this test target; their page navigation and refresh wiring require app-level checks.
final class SettingsSectionSearchContentTests: XCTestCase {

    private func target(_ title: String) -> SettingsSearchHighlightTarget {
        SettingsSearchHighlight.highlightTarget(NSTextField(labelWithString: title))!
    }

    private func hasMatchColor(_ textField: NSTextField) -> Bool {
        let attr = textField.attributedStringValue
        var found = false
        attr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attr.length)) {
            value, _, _ in
            if value as? NSColor == Appearance.searchMatchForegroundColor { found = true }
        }
        return found
    }

    func testEmptyQueryAlwaysMatches() {
        let content = SettingsSectionSearchContent()
        XCTAssertTrue(
            content.matches(""), "an empty query keeps every page available in the sidebar")
        XCTAssertTrue(content.matches("   "), "a whitespace-only query is treated as empty")
    }

    func testBaseStringIsSearchable() {
        let content = SettingsSectionSearchContent(strings: ["Appearance"], targets: [])
        XCTAssertTrue(content.matches("appea"), "a base string must drive a match")
        XCTAssertFalse(content.matches("zzzzz"), "a non-matching query must not match")
    }

    func testDynamicStringIsSearchable() {
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: ["Shortcut 1"], targets: [])
        XCTAssertTrue(
            content.matches("sho"),
            "a string published via setDynamic must be searchable — this is the sidebar-row path")
    }

    func testDynamicTargetReportsAndHighlightsMatch() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: [], targets: [SettingsSearchHighlight.highlightTarget(tf)!])
        XCTAssertTrue(
            content.matches("Sho"),
            "a dynamic highlight target alone keeps its page in the search results")
        content.highlightMatches("Sho")
        XCTAssertTrue(
            hasMatchColor(tf), "highlightMatches must light up the dynamic target's label")
    }

    /// The exact regression: rebuilt "Shortcut N" rows must light up again. Publishing the recreated
    /// rows replaces the dynamic part — the previous rows' targets are dropped (no stale highlight),
    /// the previous rows stop being searchable, and the new rows match + highlight.
    func testSetDynamicReplacesAndDropsStaleTargets() {
        let content = SettingsSectionSearchContent()
        let firstTf = NSTextField(labelWithString: "Shortcut 1")
        let firstTarget = SettingsSearchHighlight.highlightTarget(firstTf)!
        content.setDynamic(strings: ["Shortcut 1"], targets: [firstTarget])
        XCTAssertTrue(content.matches("Shortcut 1"))

        // Rebuild: refreshShortcutRows recreates the rows as fresh instances.
        let rebuiltTf = NSTextField(labelWithString: "Shortcut 2")
        let rebuiltTarget = SettingsSearchHighlight.highlightTarget(rebuiltTf)!
        content.setDynamic(strings: ["Shortcut 2"], targets: [rebuiltTarget])

        XCTAssertFalse(
            content.highlightTargets.contains { $0 === firstTarget },
            "the removed row's highlight target must be dropped, not left dangling")
        XCTAssertTrue(
            content.highlightTargets.contains { $0 === rebuiltTarget },
            "the rebuilt row's highlight target must be registered")
        XCTAssertFalse(
            content.matches("Shortcut 1"),
            "the removed row must no longer be searchable")
        XCTAssertTrue(
            content.matches("Shortcut 2"),
            "the rebuilt row must be searchable")
        content.highlightMatches("Sho")
        XCTAssertTrue(
            hasMatchColor(rebuiltTf),
            "regression: a rebuilt 'Shortcut N' row must light up when the user types 'sho'")
    }

    func testSetDynamicReplaceDoesNotAccumulate() {
        let content = SettingsSectionSearchContent(strings: ["Base"], targets: [])
        content.setDynamic(strings: ["Alpha"], targets: [target("Alpha")])
        let second = target("Bravo")
        content.setDynamic(strings: ["Bravo"], targets: [second])
        XCTAssertEqual(
            content.highlightTargets.count, 1,
            "replacing dynamic content must not accumulate targets across rebuilds")
        XCTAssertTrue(content.highlightTargets.contains { $0 === second })
        XCTAssertEqual(
            content.searchableStrings, ["Base", "Bravo"],
            "searchableStrings is base + the latest dynamic strings only")
    }

    func testClearHighlightsClearsDynamicTargets() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: [], targets: [SettingsSearchHighlight.highlightTarget(tf)!])
        content.highlightMatches("Sho")
        XCTAssertTrue(hasMatchColor(tf))
        content.clearHighlights()
        XCTAssertFalse(hasMatchColor(tf), "clearHighlights must revert dynamic targets too")
    }
}
