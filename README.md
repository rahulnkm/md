# md

A lightweight markdown editor for macOS. Visual sibling to
[stickies](https://github.com/rahulnkm/stickies) - same frosted-dark palette,
same Geist, same hover-reveal chrome - pointed at files on disk instead of
floating notes.

- Pick a folder once. Every `.md` in it shows up in the sidebar.
- Two modes: raw markdown to write in, rendered to read. `⌘E` flips.
- Autosaves 800ms after you stop typing.
- Rename from the sidebar's right-click menu, or by double-clicking the
  filename in the top bar.
- Files are plain `.md` on disk. Obsidian, Finder, git, and anything else
  read the same folder. Nothing is locked in.

## Keyboard

| Shortcut | Action |
|---|---|
| `⌘E` | Toggle Edit / Preview |
| `⌘S` | Save now |
| `⌘N` | New file |
| `⌘O` | Choose folder |
| `⌘⌥←` `⌘⌥→` | Previous / next file |

## Naming

New files are `Untitled.md`, then `Untitled (1).md`, and so on. On its first
save, a file whose body opens with a `# heading` renames itself from that
heading. After that the name is fixed - rename it yourself and it stays.

## Markdown

Headings, bold, italic, inline code, links, bullet and ordered lists, block
quotes, fenced code blocks, horizontal rules.

A lone newline inside a paragraph is a soft wrap and joins, so hard-wrapped
files read as flowing prose. For a deliberate break, end the line with two
spaces or a backslash.

Tables, footnotes, and HTML passthrough are not supported and render as plain
text rather than breaking.

Only `http`, `https`, and `mailto` links are clickable. A markdown file can
come from anywhere, and handing an arbitrary URL scheme to the system on a
single click is not a thing this app will do.

## Requirements

Targets macOS 13 and later. Built and tested on macOS 15.7 with Xcode 26.3;
earlier versions in that range are the deployment target, not something I have
run it on.

The app is not sandboxed, so it can read and write whatever folder you point it
at. It has no network code of any kind - nothing is sent anywhere.

## Build

Requires Xcode and [`xcodegen`](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen
xcodegen generate
open MD.xcodeproj
```

Then ⌘R in Xcode. `⌘U` runs the tests.

## Design docs

- [`docs/specs/2026-08-08-md-design.md`](docs/specs/2026-08-08-md-design.md) - design spec

## License

MIT - see [`LICENSE`](LICENSE).

Bundles [Geist and Geist Mono](https://github.com/vercel/geist-font) by Vercel
under the SIL Open Font License 1.1 - see
[`MD/Fonts/Geist-OFL.txt`](MD/Fonts/Geist-OFL.txt).
