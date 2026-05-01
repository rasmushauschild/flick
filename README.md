# Flick

A minimalist macOS menu bar app for daily notes and todos.

Click the menu bar icon and a small panel drops down anchored to today's date. Each day has its own page with three kinds of blocks: titles, notes, and todos. Drag the panel out and it stays floating on top of everything. All your data is stored locally as JSON.

## Features

- 📅 Per-day pages with a horizontal date scrubber
- 🧩 Three block types: title, note, and todo (with strike-through when checked)
- ✏️ A single `NSTextView` editor — native cross-paragraph text selection, cut/copy/paste, find, undo
- 🌫️ Optional frosted-glass background
- 🚀 Optional launch-at-startup
- 🔒 Local-only storage at `~/Library/Application Support/Flick/pages.json`

## Requirements

- macOS 15.7 or later
- Xcode 26+

## Build & Run

1. Open `Flick.xcodeproj` in Xcode
2. Press ⌘R

The Flick icon appears in the menu bar; click it to open the panel.

## Tests

UI tests live in `FlickUITests/`. Run them in Xcode with ⌘U, or from the command line:

```bash
xcodebuild -project Flick.xcodeproj -scheme Flick -configuration Debug test
```

## License

[MIT](LICENSE)
