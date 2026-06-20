# Moye

Moye (`墨页`) is a native macOS Markdown editor for local writing.

It is built with SwiftUI and AppKit. The editing core uses `NSTextView` for stable text input, selection, undo, and input-method behavior. Live preview is rendered separately with `WKWebView`.

[中文说明](README.zh-CN.md) · [Disclaimer](DISCLAIMER.md) · [License](LICENSE)

## Status

Moye is an early open-source project. It can already be used for local Markdown editing, but it is not a polished stable release yet.

The project goal is to build a document-first Mac Markdown editor: native menus, local files, reliable editing, live preview, practical export, and a gradual path toward a more Typora-like writing experience.

## Download

Download the latest macOS build from GitHub Releases:

<https://github.com/moye-source/moye-md/releases>

Current package format:

```text
Moye-0.1.0-macOS.zip
```

The app is currently unsigned and not notarized. macOS may show a Gatekeeper warning the first time you open it. Only run builds you trust. See [Disclaimer](DISCLAIMER.md).

## Updates

Use **Help > Check for Updates...** in the app to check whether a newer build is available.

## Feature Status

- [x] Native macOS app through Xcode
- [x] Chinese and English UI strings, with Chinese as the default language
- [x] Local Markdown source editing
- [x] `NSTextView`-based editor core
- [x] Markdown syntax highlighting
- [x] Split, editor-only, and preview-only modes
- [x] Draggable split view between editor and preview
- [x] Live HTML preview
- [x] Source-line based editor/preview scroll sync
- [x] Document outline generated from headings
- [x] Folder sidebar with full file tree browsing
- [x] File name and file content search
- [x] Quick Open
- [x] Unsaved document state
- [x] Undo, redo, cut, copy, paste, select all, find, and replace
- [x] Standard macOS menu commands
- [x] Settings from the app menu with `Command-,`
- [x] Insert commands for headings, table of contents, code blocks, tables, task lists, and images
- [x] Local image paste and drag/drop into an `assets/` folder
- [x] Table row and column editing helpers
- [x] HTML, PDF, plain HTML, PNG, and Pandoc export entries
- [x] Front matter, tables, task lists, footnotes, links, local images, and common inline styles in preview
- [x] MathJax preview for inline and block math
- [x] Mermaid preview for `mermaid` code fences
- [x] Focus mode, typewriter mode, line numbers, and auto-pair insertion
- [x] Word, character, line, and reading-time statistics
- [x] Manual update checking
- [ ] Signed and notarized releases
- [ ] Fully automatic in-app updates
- [ ] Offline bundled MathJax and Mermaid assets
- [ ] A Markdown AST pipeline for more reliable editing tools
- [ ] Typora-like source-token hiding mode
- [ ] More complete UI automation tests

## Requirements

For users:

- macOS 13 or later
- Optional: `pandoc` for Pandoc-based import/export

For development:

- Xcode with the macOS SDK
- The supported project entry is `NativeMarkdownEditor.xcodeproj`

Older Swift Package prototype entry points have been removed. Do not use `swift run`, `swift build`, or `.build/NativeMarkdownEditor.app` for real app testing.

## Development

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

Output:

```text
dist/Moye-0.1.0-macOS.zip
```

## Release Flow

GitHub Actions creates a release asset when a tag starting with `v` is pushed.

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
  MarkdownEditorInputTests.swift  Editor, renderer, file, update, and preview tests

docs/
  branding/                       Name and visual direction
  typora-feature-parity.md        Typora parity tracking
```

## Design Principles

- Native macOS first.
- Menu commands are the main command surface.
- The sidebar is for navigation, not duplicated system actions.
- Text input, selection, undo, and IME behavior should be handled by AppKit where SwiftUI is not precise enough.
- The editor core and HTML preview should stay separated.
- Typora-style editing requires Markdown structure and selection mapping, not simple string replacement.

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
