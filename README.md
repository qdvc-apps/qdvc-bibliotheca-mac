# QDVC Bibliotheca for macOS

A native macOS reference manager for academics — researchers, scholars,
students — built with SwiftUI for macOS 14 (Sonoma) and later.

Your library is a plain folder: one authoritative BibTeX file per work, plus a
Markdown file for your notes and full-text links, and a few small YAML files
for your projects, starred authors and journals. Nothing is locked in a
database, so the library stays portable, greppable, and friendly to Git,
Syncthing or iCloud Drive. The format is documented in
[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

The format is shared with the Python/GTK edition of
[QDVC Bibliotheca](https://github.com/qdvc-apps/qdvc-bibliotheca), so you can
open the same library on Linux and on a Mac. You don't need that edition to
use this one.

## Status

The window has four tabs, switched with the segmented control in the toolbar
(⌘1–⌘4), as in Activity Monitor: **Catalogue**, **Authors**, **Outlets** and
**DOI Lookup**.

- Catalogue — a three-column view: library filters (all records, by type, by full-text
  availability, by DOI status, My Works, starred authors and outlets) with
  count badges; a sortable, filterable table (PDF icon, Bibliotheca ID, Author,
  Year, J-Flags, Outlet with the nickname in bold, Title, Type); and a detail
  pane with the formatted reference.
- Built-in **APA 7** and **ACIS** styles (ACIS also shows the parenthetical and
  narrative in-text citations), remembered per workspace. Copy puts HTML, RTF
  and plain text on the pasteboard, so italics survive a paste into Word,
  Pages, Mail or Google Docs.
- Markdown notes with syntax highlighting, autosave, undo, spelling and Find.
- Multi-column sorting: click a column header, then another — the earlier
  column becomes the tie-breaker.
- Open, Quick Look (⌘Y), link and unlink PDFs and EPUBs; reveal the `.bib` or
  `.md` in Finder; open either in your text editor.
- Import BibTeX (⌘I, the toolbar, or by dropping `.bib` files on the window):
  paste or load entries, review them, and optionally allocate the new records
  to one of your works (the work you're viewing is preselected). Entries whose
  DOI is already in the library are skipped and listed.
- My Works: create a work (⌘N, or the + next to My Works in the sidebar),
  allocate records to works (right-click → Allocate to My Works…), and
  rename a record's Bibliotheca ID (F2). Renaming moves its `.bib` and `.md`
  and updates every work that cites it, and suggests an ID ending in the
  outlet's nickname.
- Authors — every author derived from your BibTeX, with starring (starred
  authors become sidebar filters) and Show Works in Catalogue.
- Outlets — journals and proceedings with starring, nicknames and J-Flags.
  J-Flag presets and their display order are set in Settings → J-Flags.
- DOI Lookup — check whether a DOI is already in the library and jump to the
  record.
- Refresh (⌘R) only re-reads files that changed on disk, so edits made in a
  text editor, by a sync client or on another machine appear quickly.

Not built yet (see the roadmap in [docs/MAINTENANCE.md](docs/MAINTENANCE.md)):
the My Works editor (renaming a work, removing citations, `published_as`), the
Validate report, and custom CSL styles.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store). The Command Line Tools
  alone can build and run the app, but `swift test` needs full Xcode.
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
swift run                       # build and launch (debug)
swift test                      # run the unit and parity tests
scripts/build-app.sh            # build "build/QDVC Bibliotheca.app" (release)
scripts/build-app.sh --install  # …and copy it to ~/Applications
```

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCBibliotheca** scheme and press ⌘R.
Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

The included GitHub Actions workflow (`.github/workflows/ci.yml`) builds and
tests the app on a macOS runner for every push, and attaches the
ad-hoc-signed `.app` to the run as a downloadable artifact.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it — no account, no
certificate, no notarisation.

A paid Developer ID is only needed to *distribute* the app so that it opens on
other Macs without a warning. If you give the ad-hoc-signed app to someone
else, macOS will block the first launch; they can allow it once in
**System Settings → Privacy & Security → Open Anyway**, or remove the
quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Bibliotheca.app"
```

Because an ad-hoc signature changes with every build, macOS may ask again for
permission to access folders such as Documents, Desktop or iCloud Drive after
you rebuild. That is expected.

## Where things are stored

- Your library: only in the workspace folder you open, in the format described
  in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).
- Preferences: the standard macOS defaults domain
  (`defaults read org.qdvc.Bibliotheca`).
- A disposable index cache: `~/Library/Caches/org.qdvc.Bibliotheca/`. It is
  kept outside the workspace so that syncing never churns on it; delete it at
  any time, or use View → Rescan All Files (⇧⌘R).

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘1–⌘4 | Catalogue, Authors, Outlets, DOI Lookup |
| ⌘O | Open workspace |
| ⌘N | New work |
| ⌘I | Import BibTeX |
| F2 | Rename the selected record's Bibliotheca ID |
| ⇧⌘W | Close workspace |
| ⌘R / ⇧⌘R | Refresh changed files / rescan everything |
| ⌘Y | Quick Look the selected record's PDF or EPUB |
| ⌘↩ | Open the selected record's PDF |
| ⇧⌘C / ⌥⇧⌘C | Copy reference (formatted / plain) |
| ⌥⌘R | Reveal the `.bib` in Finder |
| ⌘, | Settings |
| Double-click a row | Catalogue: open its PDF (or EPUB); Authors/Outlets: show its records |

## Documentation

- **[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md)** — the workspace format: folder
  layout, BibTeX, notes frontmatter, My Works, authors, outlets, YAML style.
- **[docs/MAINTENANCE.md](docs/MAINTENANCE.md)** — architecture, modules,
  behaviour to preserve, tests and CI, and the roadmap.

## License

No license has been chosen yet. Add a `LICENSE` file before publishing.
