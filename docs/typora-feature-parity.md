# Typora Feature Parity

This document tracks feature parity against official Typora documentation.

## Official Sources Checked

- `https://typora.io/`
- `https://support.typora.io/Quick-Start/`
- `https://support.typora.io/Markdown-Reference/`
- `https://support.typora.io/Images/`
- `https://support.typora.io/Export/`
- `https://support.typora.io/Math/`
- `https://support.typora.io/Draw-Diagrams-With-Markdown/`

## Current Status

| Area | Typora Capability | Status | Notes |
| --- | --- | --- | --- |
| Live Preview | Hide or smartly show Markdown syntax while editing | Planned | Requires AST-to-text-range mapping and IME-safe cursor rules. |
| Markdown Basics | Paragraphs, headings, blockquotes, ordered/unordered lists, fenced code | Done | Source editing, highlighting, and preview exist. |
| Task Lists | Render and toggle checkbox state | Partial | Preview and insertion exist; direct checkbox toggling is planned. |
| Tables | Source table support and graphical table editing | Partial | Preview and snippet insertion exist; graphical table editing is planned. |
| Math | Inline and block MathJax rendering | Partial | MathJax CDN rendering exists; offline bundled MathJax and auto-numbering are planned. |
| Diagrams | Sequence, flowchart, Mermaid diagrams | Partial | Mermaid CDN rendering exists; Typora legacy `sequence` and `flow` fences remain fallback blocks. |
| Images | Insert local image, relative path, drag/drop, paste, copy-to-folder | Partial | Local file insertion, drag/drop, paste, relative paths, and `assets/` copy exist; upload/rename/move image workflows are planned. |
| Links | Inline links, reference links, automatic URL links | Partial | Inline and automatic URL links exist; reference links are implemented for simple definitions. |
| Inline Styles | Emphasis, strong, code, strikethrough, emoji, subscript, superscript, highlight | Partial | Rendering exists; emoji shortcode coverage is intentionally small for now. |
| HTML | Preserve/render HTML snippets | Partial | Basic safe passthrough for common inline/block HTML exists. |
| Outline | Current document outline panel | Done | Sidebar outline is generated from Markdown headings and is available through the sidebar switcher. |
| Files | File tree, file list, quick open, global search | Partial | Full folder tree, filename/path/content search, Quick Open, create/rename, and Move to Trash exist; file tree and outline are switched instead of shown together; multi-select batch operations are planned. |
| Find / Replace | Find, replace, find next/previous | Partial | Native document find and replace panel entries exist; folder-level filename/path/content search exists. |
| Export | PDF, HTML, HTML without styles, image; Pandoc formats | Partial | PDF, styled/plain HTML, PNG, and Pandoc menu entries exist; Pandoc requires local installation. |
| Word Count | Words, characters, lines, reading minutes | Done | Sidebar stats include all four. |
| Focus | Focus mode and typewriter mode | Partial | Native editor toggles exist; polish is planned. |
| Auto Pair | Brackets, quotes, Markdown symbols | Partial | Basic pairing exists for common pairs. |
| Themes | CSS-based themes and custom themes | Partial | Built-in preview themes exist; custom CSS import is planned. |
| Auto Save / Recovery | Auto-save, version control, recovery | Planned | Requires document lifecycle and snapshots. |

## Implementation Rule

Do not label source-code syntax highlighting as Typora-style WYSIWYG. True WYSIWYG must hide or reveal Markdown tokens based on cursor/selection state while preserving reliable plain-text storage.
