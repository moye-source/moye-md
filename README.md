# Moye

Moye (`墨页`) is a native macOS Markdown editor for focused local writing.

It is built with SwiftUI and AppKit. The editor uses an `NSTextView` core for reliable text input, selection, undo, and input-method behavior, while the preview is rendered separately in a `WKWebView`.

[中文说明](README.zh-CN.md) · [Disclaimer](DISCLAIMER.md) · [License](LICENSE)

## Status

Moye is an early open-source project. It is usable for local Markdown editing, but it is not a polished production release yet.

The current goal is straightforward: build a document-first Mac Markdown editor that feels native, keeps local files under the user's control, and gradually evolves toward a more Typora-like editing experience without hiding unfinished architecture behind UI.

## Download

Download packaged builds from GitHub Releases:

<https://github.com/moye-source/moye-md/releases>

Release assets are distributed as macOS `.zip` files, for example:

```text
Moye-0.1.0-macOS.zip
```

The app is currently unsigned and not notarized. On macOS, Gatekeeper may warn that the app cannot be opened because the developer cannot be verified. Only run builds you trust. See [Disclaimer](DISCLAIMER.md).

## Online Updates

Moye can check for updates from GitHub Releases.

The app reads:

```text
https://api.github.com/repos/moye-source/moye-md/releases/latest
```

If a newer release exists, Moye opens the release download page or the matching release asset URL. It does not silently replace the app. A full automatic updater may be added later after code signing, notarization, and update-feed verification are in place.

## Features

- Native macOS app target through Xcode
- Chinese and English UI strings, with Chinese as the default language
- Local Markdown source editing with AppKit `NSTextView`
- Syntax highlighting for common Markdown constructs
- Split, editor-only, and preview-only modes
- Draggable split view between editor and preview
- Live HTML preview
- Source-line based editor/preview scroll sync
- Document outline generated from headings
- Folder sidebar with full file tree browsing
- File name and content search
- Quick Open
- Unsaved document state
- Undo, redo, cut, copy, paste, select all, find, and replace
- Standard macOS menu commands
- Settings from the app menu with `Command-,`
- Insert commands for headings, table of contents, code blocks, tables, task lists, and images
- Local image paste and drag/drop into an `assets/` folder
- Table row and column editing helpers
- HTML, PDF, plain HTML, PNG, and Pandoc export entries
- Front matter, tables, task lists, footnotes, links, local images, and common inline styles in preview
- MathJax preview for inline and block math
- Mermaid preview for `mermaid` code fences
- Focus mode, typewriter mode, line numbers, and auto-pair insertion
- Word, character, line, and reading-time statistics

## Requirements

- macOS 13 or later
- Xcode with the macOS SDK for development
- Optional: `pandoc` for Pandoc-based import/export

The supported project entry is:

```text
NativeMarkdownEditor.xcodeproj
```

Older Swift Package prototype entry points have been removed. Do not use `swift run`, `swift build`, or `.build/NativeMarkdownEditor.app` for real app testing.

## External Runtime Notes

Moye is a native app, but a few preview/export features currently depend on external tools or online assets:

- Math preview loads MathJax from jsDelivr.
- Mermaid preview loads Mermaid from jsDelivr.
- Pandoc import/export requires a local `pandoc` executable available from the app process.
- Update checking reads public GitHub Releases metadata.

Offline-bundled MathJax/Mermaid assets, better Pandoc path configuration, and a more complete update system are planned.

## Build

Open in Xcode:

```bash
open NativeMarkdownEditor.xcodeproj
```

Choose the `NativeMarkdownEditor` scheme, then press Run.

Command-line build and test:

```bash
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' build
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' test
```

Build and open a local debug app:

```bash
./RunNativeMarkdownEditor.command
```

Package a release zip:

```bash
./scripts/package-macos.sh 0.1.0
```

The zip will be written to:

```text
dist/Moye-0.1.0-macOS.zip
```

## Release Flow

GitHub Actions is configured to create a release asset when a tag starting with `v` is pushed.

Example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds the macOS app, creates `Moye-0.1.0-macOS.zip`, and uploads it to GitHub Releases.

## Project Structure

```text
Sources/NativeMarkdownEditor/
  AppModels.swift                 Shared models and localized strings
  ContentView.swift               Main app layout, sidebar, toolbar, status bar
  DocumentStore.swift             Document state, file operations, commands
  MarkdownEditorView.swift        NSTextView-backed Markdown editor
  MarkdownPreviewView.swift       WKWebView-backed live preview
  MarkdownRenderer.swift          Lightweight Markdown-to-HTML renderer
  MarkdownSyntaxHighlighter.swift Source editor highlighting
  NativeMarkdownEditorApp.swift   App entry point and menu commands

Tests/NativeMarkdownEditorTests/
  MarkdownEditorInputTests.swift  Core editor, renderer, file, update, and preview tests

docs/
  branding/                       Name and visual direction
  typora-feature-parity.md        Typora parity tracking
```

## Design Principles

- Native macOS first.
- Menu commands are the main command surface.
- The sidebar is for navigation, not duplicated system actions.
- Text input, selection, undo, and IME behavior should be handled by AppKit where SwiftUI is not precise enough.
- The HTML preview is separate from the editor core.
- Typora-style editing requires a real Markdown structure and selection mapping, not string-replacement tricks.

## Roadmap

- Stabilize window lifecycle and launch behavior
- Improve open/save prompts and document-state handling
- Replace the lightweight renderer with a Markdown AST pipeline
- Improve table editing beyond snippet insertion
- Add robust image asset management and broken-path repair
- Bundle MathJax and Mermaid for offline preview
- Improve Pandoc path discovery and settings
- Add signed and notarized macOS releases
- Add automatic update verification
- Add automated UI tests for open, save, export, search, and navigation flows
- Prototype a source-token hiding mode for a Typora-like single-pane editor

See [`docs/typora-feature-parity.md`](docs/typora-feature-parity.md) for feature parity tracking.

## Contributing

Contributions are welcome. Please keep changes aligned with the native macOS direction:

1. Keep UI behavior consistent with macOS document-app conventions.
2. Prefer SwiftUI for app structure and AppKit where precise text editing is required.
3. Keep renderer, editor, file state, and export logic separated.
4. Add or update tests for behavior changes.
5. Run build and tests before opening a pull request.

```bash
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' build
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' test
```

## License

Moye is released under the [MIT License](LICENSE).
