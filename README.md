# Flick, a daily notes app

Flick is a focused macOS notes app that lives in your menu bar, keeps daily notes organized automatically, and stays out of your way until you need it.

## Download

**[Download Flick for macOS](https://github.com/rasmushauschild/flick/releases/latest)** — get the latest `Flick.dmg` from [Releases](https://github.com/rasmushauschild/flick/releases).

**Requirements:** macOS 15.7 or later.

1. Download and open `Flick.dmg`.
2. Drag **Flick** into **Applications**.
3. Open Flick from Applications. If macOS blocks the first launch, right-click the app and choose **Open**.

Installed copies update in place automatically (menu bar icon → right-click → **Check for Updates…**).

## Features

### Menu bar first, window when you want
<table>
  <tr>
    <td width="50%">
      Flick lives in your menu bar and can be dragged out into its own window whenever you want more space.
    </td>
    <td width="50%">
      <img src="assets/gifs/lives%20in%20your%20menu%20bar.gif" alt="Flick menu bar and draggable window" width="100%" />
    </td>
  </tr>
</table>

### Automatic daily pages with smooth scrubbing
<table>
  <tr>
    <td width="50%">
      Each day gets its own page automatically, and you can quickly scrub through dates with satisfying haptic feedback.
    </td>
    <td width="50%">
      <img src="assets/gifs/Dates%20scroller.gif" alt="Flick date scrubber" width="100%" />
    </td>
  </tr>
</table>

### Exactly the block types you need
<table>
  <tr>
    <td width="50%">
      Keep things simple with three block types: title, text, and todo.
    </td>
    <td width="50%">
      <img src="assets/gifs/fonts.gif" alt="Flick block types" width="100%" />
    </td>
  </tr>
</table>

### Floating window that stays on top
<table>
  <tr>
    <td width="50%">
      When you drag the panel out, Flick can float above your other apps so your notes are always within reach.
    </td>
    <td width="50%">
      <img src="assets/gifs/stays%20on%20top.gif" alt="Flick floating window" width="100%" />
    </td>
  </tr>
</table>

### Looks great in light and dark mode
<table>
  <tr>
    <td width="50%">
      Flick matches your system appearance and feels at home in both light and dark themes.
    </td>
    <td width="50%">
      <img src="assets/gifs/Light%20or%20Dark.gif" alt="Flick light and dark appearance" width="100%" />
    </td>
  </tr>
</table>

### A home for permanent notes and links
<table>
  <tr>
    <td width="50%">
      Use the permanent notes space for long-term notes, link collections, and your best ideas.
    </td>
    <td width="50%">
      <img src="assets/gifs/permanent%20notes.gif" alt="Flick permanent notes" width="100%" />
    </td>
  </tr>
</table>

## Build and Run

1. Open `Flick.xcodeproj` in Xcode.
2. Select the `Flick` scheme.
3. Press `⌘R` to build and run.

Or run from Terminal:

```bash
xcodebuild -project Flick.xcodeproj -scheme Flick -configuration Debug build
```

Hope you enjoy using Flick.
