# Flick — Project Notes for Claude

A macOS menu-bar app for daily notes & todos. SwiftUI + AppKit hybrid. macOS 15.7+, Xcode 26, Swift 5. Bundle ID `com.xolo.Flick`. Sandboxed, `LSUIElement = YES` (no Dock icon).

## File map

```
Flick/
  FlickApp.swift                 — @main + NSApplicationDelegateAdaptor
  AppDelegate.swift              — NSStatusItem + NSWindow lifecycle, key/mouse monitors,
                                    settings observation, custom close-button positioning,
                                    --ui-testing launch flag handling
  Models/
    Block.swift                  — Block(id, type, text, isChecked) + BlockType enum
    DayPage.swift                — DayPage(id: "yyyy-MM-dd", blocks: [Block])
    Store.swift                  — @Observable, persists [String: DayPage] as JSON;
                                    hasContent ignores whitespace; removePage(id:)
                                    drops empty pages; uses temp dir under --ui-testing
    AppSettings.swift            — @Observable: isTransparent, launchAtStartup
  Views/
    RootView.swift               — top VStack (date scrubber + PageView), and overlays
                                    for the red close dot (top-leading) and the
                                    notes/calendar mode toggle (top-trailing).
                                    Uses .ignoresSafeArea(.top) so overlays pin to the
                                    actual window edge.
    DateScrubber.swift           — horizontal date strip with hover-to-reveal numbers,
                                    bold today, content-dot under dates with text,
                                    smooth scroll-on-tap (custom Task-driven animation
                                    talking to ScrollPosition).
    PageView.swift               — owns blocks: [Block]; reload appends an empty .note
                                    buffer; save strips it; if no real content remains
                                    it calls store.removePage to wipe the page.
                                    Switches via .id(mode) on PageMode change.
    AddBlockBar.swift            — Title / Note / Todo convert buttons + settings gear.
                                    Buttons are always enabled and post
                                    .flickConvertParagraph notifications.
    SettingsPanel.swift          — popover for transparent background + launch-at-startup
    BlockAttributedString.swift  — [Block] <-> NSAttributedString. Defines the
                                    .flickBlockType / .flickIsChecked attribute keys,
                                    the paragraph styles (todo gets a head indent for
                                    the checkbox gutter), and the title font
                                    (NocturneSerifTest-SemiBold 17pt).
    FlickTextEditor.swift        — THE EDITOR. NSViewRepresentable wrapping a custom
                                    NSTextView ("FlickTextView"). See section below.
    BlockRow.swift               — ⚠️ unused after the NSTextView refactor; only its
                                    Notification.Name extensions are still imported.
                                    Safe to retire eventually.
FlickUITests/
  FlickUITests.swift             — two XCUITest cases. App honors --ui-testing to
                                    auto-show the window and use a temp Store dir.
```

## Critical invariants — DO NOT BREAK

### 1. The trailing-buffer line
The text storage's **last paragraph is always an empty `.note`**. This sidesteps an old bug where empty trailing `.todo` paragraphs didn't get their checkbox drawn (TextKit didn't always lay out a line fragment for an empty paragraph at the document end).

- `PageView.reload()` appends `Block(.note, "")` when loading.
- `FlickTextEditor.Coordinator.ensureTrailingBuffer(in:)` runs after every `textDidChange` and after `replaceContents`. If the last paragraph isn't already an empty `.note`, it appends `"\n"` with `.note` attributes. **Cursor and typingAttributes are saved/restored around the append** — without that, the cursor jumps onto the new buffer line.
- `PageView.save()` strips the trailing buffer(s) before persisting; if no real content remains it calls `store.removePage(id:)`.

### 2. Paragraph-level attributes
Every paragraph carries `.flickBlockType` and `.flickIsChecked` on its full range (including its terminating `\n`). `Coordinator.ensureParagraphAttributes(in:)` walks all paragraphs after every text change, reads the type from the first character, and re-applies `BlockAttributes.attributes(for:)` so the run is uniform.

### 3. typingAttributes follow the cursor
`ensureParagraphAttributes` sets `textView.typingAttributes` from the **character at the cursor**, not from the last paragraph. (Earlier code used the last paragraph; that caused typing in any non-last paragraph to inherit `.note` from the buffer.)

### 4. `NSString.paragraphRange(for:)` already includes the terminator
**Don't expand it.** We had a long-running bug where `convertCurrentParagraph` and `toggleTodoChecked` added another `\n` to the range and spilled attributes onto the next paragraph — turning the next line into a checkbox too. Both methods now use the range as returned.

## FlickTextView (the custom NSTextView)

Lives in `Flick/Views/FlickTextEditor.swift`. Key responsibilities:

- **Checkbox drawing** — `draw(_:)` → `drawCheckboxes(in:)` → `todoCheckboxEntries()`. Iterates line fragments via `enumerateLineFragments` and matches each line back to its paragraph; falls back to `extraLineFragmentRect` for empty trailing paragraphs (covered by the buffer invariant in practice).
- **Click on checkbox** — `mouseDown(with:)` → `didHandleCheckboxClick(at:)` checks the gutter region (`x < BlockAttributes.todoIndent`) and toggles via `toggleTodoChecked(paragraphRange:)`.
- **Cursor over checkbox** — NSTrackingArea with `.cursorUpdate` + `.mouseMoved`. Override of `mouseMoved(with:)` short-circuits when over a checkbox so NSTextView's I-beam doesn't override our arrow. Tracking areas rebuilt on `didChangeText`.
- **Backspace on empty title/todo** — `keyDown(with:)` (keyCode 51) calls `demoteEmptyTitleOrTodoToNote()`. Plain backspace on `.note` falls through to NSTextView's default (merge with previous paragraph).
- **Plain Return on empty title/todo** — `insertNewline(_:)` override calls `demoteEmptyTitleOrTodoToNote()` before falling through to super.
- **Shift+Return** — `keyDown` intercept calls `insertParagraphAbove()`.
- **Block conversion** — `convertCurrentParagraph(to:)`. AddBlockBar posts `.flickConvertParagraph` (object: `BlockType.rawValue`); the coordinator's NotificationCenter observer calls this method. **Note**: it does NOT fire `delegate.textDidChange` afterwards — adding that caused the wrong paragraph to convert when on the bottom buffer line. Conversion intentionally has no effect on the empty buffer line.
- **Boundary disambiguation** — `paragraphRanges(at:in:)` walks `enumerateSubstrings(.byParagraphs)` with a strict `<` boundary check so a position at the start of paragraph N+1 doesn't also match paragraph N's enclosing range. Used by the demote helpers.

## SwiftUI binding writes are deferred
`Coordinator.syncBlocksFromStorage()` and `updateFocusedBlockType()` write to `parent.blocks` / `parent.focusedBlockType` via `DispatchQueue.main.async`, so writes don't happen during a SwiftUI view-update pass (otherwise: "Modifying state during view update" warnings).

## UI / cosmetics

- **Title font**: `NocturneSerifTest-SemiBold` 17pt (postscript-named in `BlockAttributes.titleFont`). Falls back to system semibold 17 if not installed.
- **Transparent mode**: NSVisualEffectView with `.menu` material, `.behindWindow` blending. Toggling reapplies in `AppDelegate.updateAppearance`.
- **Window**: `.titled, .closable, .resizable, .fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`, miniaturize/zoom hidden, min size 240×360. Standard close button is repositioned to (13, titleBarHeight - 13 - buttonHeight) and pinned via KVO + `windowDidResize` so AppKit can't snap it back.
- **Notes/calendar mode toggle**: SwiftUI overlay top-trailing on the outer VStack, padding `(top: 6, trailing: 7)`, `.ignoresSafeArea(.top)`.
- **Red close dot**: was a SwiftUI custom red Circle overlaid top-leading; reverted to the standard NSWindow close button (we still keep the `.flickClosePressed` Notification name in case we go back to a custom one for the borderless / liquid-glass refactor).

## Build / run

```bash
cd "Flick"
xcodebuild -project Flick.xcodeproj -scheme Flick -configuration Debug build
```

In Xcode: ⌘R. Status item appears in menu bar; click it to toggle the window. Drag the window to detach (window level becomes `.floating`).

If a Flick instance is stuck (Xcode debugger may hold it):
```bash
pkill -9 -f "Flick.app/Contents/MacOS/Flick"
```

## Tests

```bash
pkill -9 -f "Flick.app/Contents/MacOS/Flick" 2>/dev/null
xcodebuild -project Flick.xcodeproj -scheme Flick -configuration Debug test
```

`--ui-testing` launch flag:
- Auto-shows the window (no need to click the menu-bar icon).
- Routes `Store` to a per-launch temp directory so tests never touch real notes.

Accessibility identifiers tests rely on:
- `flickEditor` — the NSTextView (set via `setAccessibilityIdentifier`)
- `convertButton.title` / `convertButton.note` / `convertButton.todo` — AddBlockBar buttons

## Conventions / preferences

- Don't add emojis to user-facing UI unless asked.
- Don't create README/docs files unless asked.
- Use `Edit` over `Write` for existing files; only `Write` for genuinely new files.
- Sound on task completion: `afplay /System/Library/Sounds/Glass.aiff` (user preference).
- `gh` CLI requires `zsh -ic '...'` so it picks up the user's `GH_TOKEN` from `.zshrc`.

## Future work (discussed, not done)

- **Liquid-glass design (macOS Tahoe)**: switch to `.borderless` style mask + apply SwiftUI `glassEffect()` to the root + custom red close dot (we have the scaffolding for it). Would require ditching the standard NSWindow chrome.
- **Larger window corner radius**: the OS clips at the standard ~10pt for `.titled` windows; can only be increased by going borderless.
- **Retire `Flick/Views/BlockRow.swift`**: unused after the NSTextView refactor; just the `Notification.Name` extensions in it are still imported (move them into `BlockAttributedString.swift` or `FlickTextEditor.swift`).

## Repo

- Public: [github.com/rasmushauschild/flick](https://github.com/rasmushauschild/flick)
- License: MIT (`LICENSE` at repo root)
- `main` is current; `nstextview-refactor` is historical and equal to `main` (safe to delete).
