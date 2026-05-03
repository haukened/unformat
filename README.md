# Unformat

A lightweight macOS menu bar utility that strips rich-text formatting from your clipboard, so you always paste plain text.

## The Problem

You copy text from a webpage, email, or document and paste it somewhere else — but it brings along unwanted fonts, colors, and styling. You just wanted the words.

## The Solution

Unformat sits quietly in your menu bar and removes rich-text formatting (RTF, HTML, RTFD) from your clipboard, leaving only clean plain text.

## Features

- **Automatic Stripping** — Monitors your clipboard in real time and automatically strips formatting as soon as you copy
- **Strip & Paste Hotkey** — Press `⌃⌥⌘V` (Control + Option + Command + V) to strip formatting and paste in one step
- **Manual Strip** — Click "Strip Clipboard Now" from the menu bar for on-demand stripping
- **Launch at Login** — Start Unformat automatically when you log in
- **Smart Detection** — Only strips when rich text is present; leaves plain text, files, and images untouched

## Installation

Download the latest release from the [Releases](https://github.com/haukened/unformat/releases) page.

### Requirements

- macOS 26.0 or later
- Accessibility permission (required for the Strip & Paste hotkey)

### Gatekeeper Warning

Unformat is currently distributed as an unsigned application. When you first open it, macOS Gatekeeper will display a warning that the app is from an unidentified developer. To open it, right-click (or Control-click) the app and select **Open**, then click **Open** in the dialog. You only need to do this once.

>[!WARNING]
> This may expose your machine to security risks if you download and run untrusted software. Only download Unformat from the official GitHub repository or website, and only if you trust the source (me!). I plan to sign the appl in the future, but for now i'm testing it without investing in an Apple Developer account.

## Usage

Once running, Unformat appears as an icon in your menu bar. From there you can:

1. **Toggle Automatic Stripping** — Enable to automatically strip formatting whenever you copy rich text
2. **Strip Clipboard Now** — Manually strip the current clipboard contents
3. **Toggle Launch at Login** — Start Unformat when your Mac boots

### Strip & Paste

The global hotkey `⌃⌥⌘V` strips formatting from the clipboard and immediately pastes into the active application. macOS will prompt you to grant Accessibility permission the first time you use this feature.

## How It Works

Unformat monitors your system clipboard for changes. When it detects rich-text content (RTF, HTML, RTFD, or legacy NeXT formats), it extracts the plain text and rewrites the clipboard with just the text — no formatting attached.

A 150ms debounce ensures the source application has finished writing all clipboard representations before Unformat processes them.

## Building from Source

Open `unformat.xcodeproj` in Xcode and build. No third-party dependencies — Unformat uses only Apple system frameworks.

## License

[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)

## Support

- 🌐 [Website](https://unformat.hauken.us)
- 🍺 [Buy me a Beer](https://beer.hauken.us)

---

Copyright © David Haukeness
Released under the [GNU General Public License v3.0](./LICENSE)
