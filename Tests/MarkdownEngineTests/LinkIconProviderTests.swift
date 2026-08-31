//
//  LinkIconProviderTests.swift
//  MarkdownEngineTests
//
//  `LinkIconProvider` is the fifth service — the one that adds a small icon
//  before a link's label without touching the source. These tests pin the
//  three behaviors that matter: existing embedders see zero attribute
//  change (the no-op default), a provider returning an image writes the
//  attribute pair on the opening marker's first character, and an active
//  link (caret inside) skips decoration so the revealed `[` doesn't
//  collide with the icon.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("LinkIconProvider")
struct LinkIconProviderTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    private struct StaticIconProvider: LinkIconProvider {
        let image: NSImage
        let onlyForKind: LinkKind?
        init(_ image: NSImage, onlyForKind: LinkKind? = nil) {
            self.image = image
            self.onlyForKind = onlyForKind
        }
        func icon(for href: String, kind: LinkKind, range: NSRange) -> NSImage? {
            if let onlyForKind, onlyForKind != kind { return nil }
            return image
        }
        func fingerprint() -> AnyHashable { ObjectIdentifier(image).hashValue }
    }

    private func makeImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus(); NSColor.red.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill(); img.unlockFocus()
        return img
    }

    /// Look up the styled attributes on the character at `location`.
    private func attrs(at location: Int, in styled: [StyledRange]) -> [NSAttributedString.Key: Any] {
        var merged: [NSAttributedString.Key: Any] = [:]
        for (range, dict) in styled where NSLocationInRange(location, range) {
            for (k, v) in dict { merged[k] = v }
        }
        return merged
    }

    @Test("default provider writes no linkIcon attributes")
    func defaultProviderWritesNothing() {
        let styled = MarkdownASTStyler.styleAttributes(
            text: "[docs](docs/)", fontName: fontName, fontSize: base,
            configuration: .default
        )
        // The opening `[` is at index 0.
        #expect(attrs(at: 0, in: styled)[.linkIcon] == nil)
    }

    @Test("a URL-link icon lands on the opening `[`")
    func urlLinkIconOnOpeningMarker() {
        let image = makeImage()
        var config = MarkdownEditorConfiguration.default
        config.services = MarkdownEditorServices(linkIcons: StaticIconProvider(image, onlyForKind: .markdownURL))
        let styled = MarkdownASTStyler.styleAttributes(
            text: "[docs](docs/)", fontName: fontName, fontSize: base,
            configuration: config
        )
        let a = attrs(at: 0, in: styled)
        #expect((a[.linkIcon] as? NSImage) === image)
        #expect(a[.linkIconBounds] is NSValue)
        // Net kern is positive and roughly the icon-side-length; the exact
        // number depends on the shrink pass compensation, so allow a range.
        let kern = a[.kern] as? CGFloat ?? 0
        #expect(kern > 10 && kern < 40)
    }

    @Test("a wiki-link icon lands on the opening `[[`'s first char")
    func wikiLinkIconOnOpeningMarker() {
        let image = makeImage()
        var config = MarkdownEditorConfiguration.default
        config.services = MarkdownEditorServices(linkIcons: StaticIconProvider(image, onlyForKind: .wikiLink))
        let styled = MarkdownASTStyler.styleAttributes(
            text: "[[Note]]", fontName: fontName, fontSize: base,
            configuration: config
        )
        #expect((attrs(at: 0, in: styled)[.linkIcon] as? NSImage) === image)
    }

    @Test("active link (caret inside) skips the icon")
    func activeLinkSkipsIcon() {
        let image = makeImage()
        var config = MarkdownEditorConfiguration.default
        config.services = MarkdownEditorServices(linkIcons: StaticIconProvider(image))
        // Caret inside `[docs](docs/)` — index 2 is inside "docs".
        let styled = MarkdownASTStyler.styleAttributes(
            text: "[docs](docs/)", fontName: fontName, fontSize: base,
            caretLocation: 2,
            configuration: config
        )
        #expect(attrs(at: 0, in: styled)[.linkIcon] == nil)
    }

    @Test("kind lets the provider treat URL vs wiki links differently")
    func kindDrivesProviderDecision() {
        let image = makeImage()
        var config = MarkdownEditorConfiguration.default
        // Only URL links get the icon.
        config.services = MarkdownEditorServices(linkIcons: StaticIconProvider(image, onlyForKind: .markdownURL))
        let styled = MarkdownASTStyler.styleAttributes(
            text: "[a](x) then [[Note]]", fontName: fontName, fontSize: base,
            configuration: config
        )
        // URL link's `[` is at 0; wiki link's `[[` starts at 12.
        #expect((attrs(at: 0, in: styled)[.linkIcon] as? NSImage) === image)
        #expect(attrs(at: 12, in: styled)[.linkIcon] == nil)
    }
}
