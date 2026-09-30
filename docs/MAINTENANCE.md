# QDVC Bibliotheca for macOS — Maintenance Guide

This guide covers the architecture and upkeep of QDVC Bibliotheca for macOS.
The on-disk workspace format is specified in
[FILE_FORMAT.md](FILE_FORMAT.md); read that first.

The app began as a port of the Python/GTK edition of QDVC Bibliotheca
(<https://github.com/qdvc-apps/qdvc-bibliotheca>) and shares its file format,
so the two can open the same library. This repository does not depend on that
codebase: it builds, runs and tests on its own. The Python edition is
mentioned below only as the origin of some modules, and as the optional source
of the parity fixtures (§5).

---

## 1. Layout

```
(repository root)
  Package.swift                 SwiftPM manifest (tools 5.10, macOS 14+)
  Sources/
    BibliothecaCore/            pure model layer — Foundation + Yams only
    QDVCBibliotheca/            SwiftUI/AppKit front-end (the executable)
  Tests/BibliothecaCoreTests/   XCTest: parity + workspace tests
    Fixtures/parity.json        committed reference outputs (see §5)
  tools/make_fixtures.py        optional: regenerates parity.json (see §5)
  tools/make_icon.py            regenerates the app icon (see §1.1)
  Resources/Info.plist          bundle metadata used by scripts/build-app.sh
  Resources/AppIcon.svg         the icon's vector master (generated)
  Resources/AppIcon.icns        the icon, all sizes (generated)
  scripts/build-app.sh          builds and ad-hoc signs the .app
  docs/FILE_FORMAT.md           the workspace format specification
  .github/workflows/ci.yml      build + test on a GitHub macOS runner
```

There is deliberately no `.xcodeproj`: Xcode opens `Package.swift` directly,
and a hand-maintained project file would be one more thing to keep in sync.
The `.app` bundle is assembled by `scripts/build-app.sh` from the SwiftPM
release binary, `Resources/Info.plist` and `Resources/AppIcon.icns`.

### 1.1 App icon

The icon is a shelf of frosted-glass books in the macOS 26 Liquid Glass style
(violet "Dusk" palette). `tools/make_icon.py` draws it as SVG and writes
`Resources/AppIcon.svg` and `Resources/AppIcon.icns`; both are committed, so
building needs nothing extra. To change the design or palette, edit the
constants at the top of the script and run `python3 tools/make_icon.py`
(needs `rsvg-convert`: `brew install librsvg`). Every size in the `.icns` is
rendered from the vector, not scaled down, so small sizes stay sharp.

The geometry follows Apple's macOS icon template: an 824 × 824 tile centred
on a 1024 × 1024 canvas (100 px transparent margin), with a 185.4 px corner,
and a black drop shadow (28 px blur, 12 px down, 50 %). The corner uses
Apple's *continuous-curvature* rounded rectangle: the curve UIKit draws, as
reverse-engineered and published by PaintCode. It is not a superellipse; a
whole-shape superellipse looks slightly too round, because it starts curving
before Apple's corner does. macOS applies no mask to Mac app icons, so the
shape, margin and shadow must be baked into the artwork, as the script does.

If Finder or the Dock keeps showing an old icon after a rebuild, that's the
system icon cache; re-copying the app (for example
`scripts/build-app.sh --install`) usually refreshes it.

`Package.resolved` is committed. It pins the exact dependency versions (only
Yams today) so every checkout and every CI run builds the same code. Update it
deliberately with `swift package update`, then commit the result together with
any code changes it needs.

The package uses Swift language mode 5 (tools version 5.10), so strict
concurrency checking is off. The UI types are `@MainActor`; `Workspace` is
marked `@unchecked Sendable` because it is built on a background task and then
handed to the main actor, never shared concurrently.

---

## 2. Modules

`BibliothecaCore` (no AppKit or SwiftUI; everything here is unit-tested):

| File | Responsibility | Origin in the Python edition |
| --- | --- | --- |
| `TextSupport.swift` | regex wrapper, Python-compatible string helpers, atomic file IO | — |
| `Naming.swift` | IDs, slugs, author ids, nicknames, DOI normalisation | `naming.py` |
| `BibTeX.swift` | single-entry parser, multi-entry splitter | `bibtex.py` (fallback parser) |
| `Builtin.swift` | name splitting, initials, field cleaning, type labels | `builtin.py` |
| `APA7.swift`, `ACIS.swift` | built-in citation styles, ACIS in-text and year letters | `builtin_apa7.py`, `builtin_acis.py` |
| `YAML.swift` | YAML value model; reads with Yams, writes PyYAML-style | PyYAML |
| `MarkdownIO.swift` | frontmatter + notes files | `markdown_io.py` |
| `Models.swift` | `Record`, `MyWork`, `Author`, `Outlet` | `models.py` |
| `Workspace.swift` | loading, index cache, derivation, queries, mutations | `workspace.py` |
| `Validation.swift` | the Validate report | `workspace.validate`, `ui_prefs.py` |
| `CatalogueSupport.swift` | sort keys, J-Flag ordering, style ids, markup → RTF | `catalogue_sort.py` |

`QDVCBibliotheca` (the app):

| File | Responsibility |
| --- | --- |
| `BibliothecaApp.swift` | `@main` app, single `Window` scene, app delegate |
| `Commands.swift` | menu-bar commands and shortcuts |
| `ContentView.swift` | tab switching (toolbar segmented control), `MainSplitView` (the one split view and search field for all tabs), the one sheet host, welcome screen |
| `AuthorsView.swift`, `OutletsView.swift`, `DOILookupView.swift` | the Authors, Outlets and DOI Lookup tabs: sidebar, list and detail pane of each; `RecordList` and `StarButton` |
| `Sheets.swift` | Allocate, New Work, Rename, Nickname and J-Flags sheets |
| `SidebarView.swift` | library filters with count badges |
| `CatalogueTableView.swift` | the records `Table`, `CatalogueRow`, record context menu |
| `DetailView.swift` | reference, in-text citations, copy/open actions, notes |
| `ImportSheet.swift` | Import BibTeX sheet with the allocate-to-work picker |
| `NotesEditor.swift` | `NSTextView` wrapper (Markdown notes, or plain text with `markdown: false`) and Markdown highlighter |
| `AppModel.swift` | all window state and actions |
| `Prefs.swift`, `SettingsView.swift` | preferences and the Settings window (General, J-Flags) |
| `Platform.swift` | pasteboard, Finder, text editor, markup → `AttributedString` |

`AppModel` is the single `@Observable` object behind the window. Every action
that changes the workspace goes through it, and it then calls
`refreshSidebar()` / `refreshRows()` so the counts, rows and detail pane stay
consistent. Rows are rebuilt as `CatalogueRow` value snapshots (filter →
search → `sort(using: sortOrder)`), which keeps `Table` diffing cheap.

`Record` and the other model classes are not observable. When a mutation
changes state a view shows directly from a `Record` (currently only full-text
links), `AppModel` bumps a revision counter (`fulltextRevision`) that the
reading helper (`hasFulltext`) touches, so SwiftUI re-renders. Follow the same
pattern for future record mutations.

---

## 3. Behaviour that must be preserved

- **File formats.** Everything in [FILE_FORMAT.md](FILE_FORMAT.md). In
  particular, `YAMLEmitter` reproduces PyYAML's `safe_dump(...,
  allow_unicode=True)` layout and quoting, so files written by this app and by
  the Python edition are identical. Known, harmless differences are listed in
  the `YAMLEmitter` doc comment. If you change the format, update
  FILE_FORMAT.md in the same commit.
- **Critical ordering rule.** Notes and frontmatter share one `.md` file.
  `AppModel.flushNotes()` must run before any frontmatter write
  (`setFulltext`, and any future writer). `Workspace.writeNotes` re-reads the
  frontmatter from disk rather than trusting a copy taken when the record was
  selected.
- **Notes autosave.** Notes are written 1.5 s after the last keystroke, on
  record switch, before refresh/close, when the app resigns active, and on
  quit. When the app becomes active again, the current note is re-read if it
  has no unsaved edits, so edits made in another editor show up.
- **Nothing in a column may demand a large minimum size.** If any view's
  minimum height exceeds the window, the whole split view is laid out taller
  than the window and shown from its middle. The detail pane then looks blank
  and the sidebar and table look scrolled ("paged down"). Two rules follow:
  - Every `NSViewRepresentable` implements `sizeThatFits(_:nsView:context:)`
    and returns the proposed size (as `NotesEditor` does). Otherwise SwiftUI
    falls back to the AppKit fitting size, which for scroll views can be huge.
  - Never put `.fixedSize(horizontal: false, vertical: true)` on wrapping
    text inside a column. SwiftUI measures minimum sizes at near-zero widths,
    where such text is thousands of points tall. Use `.layoutPriority` to
    favour text over a flexible neighbour instead (as `DetailView` does).
- **One split view for every tab.** `MainSplitView` is a single
  `NavigationSplitView` whose three columns switch content with the tab. Do not
  give a tab its own layout without a sidebar, or its own split view: the
  toolbar centres the tab control over the area beside the sidebar, so the
  control jumps whenever the sidebar appears or disappears. The HIG treats
  the sidebar as persistent window structure that people hide themselves
  (View → Hide Sidebar). The search field is attached once, too, and routes to
  the current tab's filter text.
- **One sheet at a time.** Every sheet is a case of `ActiveSheet`, presented
  by a single `.sheet(item: $model.activeSheet)` in `ContentView`. Sheets only
  collect input; the `AppModel` method that applies the change also closes
  the sheet. Methods that can fail with a message the user should fix (rename,
  nickname) throw instead, so the sheet stays open and shows the problem.
- **Return triggers a sheet's default button even inside a text field**
  (standard AppKit behaviour). If Return in a field should do something else,
  move `.defaultAction` to that button while the field has text, as
  `JFlagsSheet` does.
- **Renames flush notes first.** `performRename` writes pending notes before
  the `.md` moves, then updates `notesRecordID` so autosave follows the file.
- **Load-bearing strings.** The type labels (`Builtin.typeLabels`) and the
  citation-style ids (`__apa__`, `__acis__`) keep the same values as in the
  Python edition.

---

## 4. Deliberate differences from the Python edition

- **Parser.** The port always uses the fallback BibTeX parser. It works on
  Unicode scalars so indices match Python's (Swift would treat `\r\n` as one
  `Character`). `@string` macros and `#` concatenation are not expanded, as in
  the Python fallback.
- **Index cache.** Kept in `~/Library/Caches/org.qdvc.Bibliotheca/index-<hash>.json`
  instead of `.qdvc-index.json` in the workspace, so a synced workspace is not
  rewritten by whichever machine opened it last. Each record stores the
  modification times of its `.bib` and `.md`; a load re-parses only files that
  changed and picks up new ones, so **Refresh** is incremental and
  **Rescan All Files** forces a full parse. Bump `IndexCache.currentVersion`
  when `CachedRecord` changes.
- **Hidden folders** under `bibtex/` (such as Syncthing's `.stversions`) are
  skipped when scanning.
- **Unparseable `my_works` YAML** is left untouched on load instead of being
  rewritten from its file name.
- **Author de-duplication.** A record counts once per author even when the
  name is listed twice. The Python edition (as of the port) counts it twice,
  because of a bug in its `_derive_authors`.
- **DOI Lookup** shows its result in the tab's detail pane instead of jumping
  to the Catalogue as the GTK app does; Show in Catalogue is one click away.
- **Preferences** live in `UserDefaults` (keys in `Prefs.Key`), not in the
  Python YAML config.

Two quirks of the Python formatters are reproduced for parity rather than
fixed. They are worth fixing in both editions together, then regenerating the
fixture: for 21 or more authors,
`collapse_artefacts` turns APA's ", . . . " ellipsis into ",.."; and a
brace-protected corporate author such as `{Association for Information
Systems}` has its braces stripped before splitting, so it renders as
"Systems, A. F. I.".

---

## 5. Tests

`swift test` runs two suites:

- **ParityTests** feed the inputs in `Fixtures/parity.json` through the Swift
  core and compare with the reference outputs recorded there: BibTeX parsing and
  index fields, APA 7 and ACIS (reference, in-text, author lists), entry
  splitting, naming/slug/DOI helpers, name splitting, YAML scalar quoting and
  documents, frontmatter parsing, ACIS disambiguation, and small helpers.
- **WorkspaceTests** build a scratch workspace and exercise loading, queries,
  author/outlet derivation and persistence, nickname renames, `my_works`
  canonicalisation, notes, full-text links, the incremental cache, import,
  rename, validation and work allocation.

`parity.json` is committed, so the tests need nothing outside this
repository. The reference outputs in it were produced by running the Python
edition's code. To re-check against a newer Python edition (optional), point
the generator at a checkout of it, then rerun the tests:

```sh
python3 tools/make_fixtures.py --python-repo /path/to/qdvc-bibliotheca
swift test
```

To add a parity case, add an input to the lists in `tools/make_fixtures.py`;
the Swift side iterates over whatever is there. If you decide to diverge from
the Python edition deliberately, move that case into `WorkspaceTests` (or a
new XCTest) with the expected value written out, and record the difference
in §4.

**Continuous integration.** `.github/workflows/ci.yml` builds the app, runs
`swift test` and builds the ad-hoc-signed bundle on a GitHub-hosted macOS
runner for every push and pull request. The bundle is uploaded as a workflow
artifact. GitHub's macOS runners are free for public repositories.

---

## 6. Roadmap

Model support already exists (and is tested) for the items marked *core
ready*; they need UI.

1. ~~Authors and Outlets~~ — done: tabs with star toggles, "Show in
   Catalogue" (a non-starred author or outlet appears under *Query Results* in
   the sidebar, like the GTK transient node), nicknames and J-Flags.
2. ~~Import BibTeX~~ — done: `ImportSheet` via File → Import BibTeX… (⌘I), the
   toolbar, or dropping `.bib` files on the window. The sheet preselects the
   work shown in the sidebar (`AppModel.currentWorkKey`); after import,
   `AppModel.performImport` allocates, switches to that work, selects the first
   new record, and reports skipped entries (duplicate DOI or existing ID) in
   an alert, or else shows a transient subtitle message.
3. **My Works**: ~~create~~ and ~~allocate~~ are done (`NewWorkSheet`,
   `AllocateSheet`). Still to do: an editor for name, cites (including removing
   a citation) and `published_as` (the GTK `MyWorkEditor`), and allocating by
   dragging rows from the table onto a work in the sidebar. Removing citations
   needs a small `Workspace` addition.
4. ~~Rename Bibliotheca ID~~ — done (`RenameSheet`, F2). Still to do: the
   **Validate** report window (*core ready*: `Workspace.validate`).
5. ~~DOI lookup~~ — done (DOI Lookup tab).
6. ~~J-Flag presets editor~~ — done (Settings → J-Flags). Still to do:
   sort-order persistence and multi-record selection in the Catalogue table
   (the allocate sheet already accepts several records).
7. **CSL styles**: render with citeproc-js inside `JavaScriptCore` (bundled as
   a resource), listing the workspace's `csl/` files in the style picker. Until then, a stored CSL style id falls back to APA.
8. **Live refresh** with FSEvents (the incremental cache makes a reload after
   each change cheap).
