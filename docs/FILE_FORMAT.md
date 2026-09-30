# Workspace File Format

A QDVC Bibliotheca library ("workspace") is an ordinary folder of text files.
Nothing is kept in a database, so a workspace can be versioned with Git,
synced with Syncthing or iCloud Drive, searched with `grep`, and edited by
hand.

The same format is used by the Python/GTK edition of QDVC Bibliotheca, so
either app can open a workspace written by the other. This document is the
reference for the Mac app; the Mac app does not need the Python edition.

---

## 1. Layout

```
(workspace root)/
    bibtex/<A..Z>/<bibliotheca_id>.bib     one entry per file — authoritative
    markdown/<A..Z>/<bibliotheca_id>.md    YAML frontmatter + free-form notes
    my_works/*.yml                         the user's own works (any file stem)
    authors/<SURNAME_GivenNames>.yml       derived authors + star state
    outlets/<nickname-or-slug>.yml         derived journals/proceedings + user state
    csl/*.csl                              optional CSL citation styles
```

A folder counts as a workspace if it contains `bibtex/` or `markdown/`.
Creating a new workspace creates `bibtex/`, `markdown/` and `my_works/`; the
other folders appear as they are needed.

The Python edition may also leave a `.qdvc-index.json` cache in the root. It
is disposable, and the Mac app neither reads nor writes it (it keeps its own
cache in `~/Library/Caches/org.qdvc.Bibliotheca/`).

Hidden files and folders (names starting with `.`) are ignored when scanning
`bibtex/`, so sync-tool folders such as Syncthing's `.stversions` do not
create phantom records.

### 1.1 Bibliotheca IDs and shards

The **Bibliotheca ID** is the file stem of a record's `.bib` file and is the
app's primary key. The convention is `AuthorSurnamesYear_suffix`, for example
`SmithJones2025_MISQ`, where the suffix is usually the outlet's nickname.

The ID is independent of the citation key inside the `.bib`. The two may
differ; the Validate report lists mismatches, but the app always keys off the
file name.

IDs contain only `A–Z a–z 0–9 _ -`. When an ID is made from arbitrary text
(for example a citation key during import): trim it, turn each run of
whitespace into `_`, drop every other disallowed character, then trim leading
and trailing `_` and `-`.

The **shard** folder is the upper-cased first character of the ID when that
character is a letter, otherwise `_`. So `SmithJones2025_MISQ` lives at
`bibtex/S/SmithJones2025_MISQ.bib` and `markdown/S/SmithJones2025_MISQ.md`,
and `2020Report` at `bibtex/_/2020Report.bib`.

---

## 2. BibTeX (`bibtex/<shard>/<id>.bib`)

Each file holds one BibTeX entry, kept exactly as it came from the publisher
or reference database. The app never rewrites these files, except to move one
when a record is renamed.

Parsing rules:

- The entry type (`@article`, `@InProceedings`, …) is lower-cased. Field
  names are lower-cased.
- Values may be brace-delimited (`{…}`, nesting allowed), quote-delimited
  (`"…"`), or bare (`2025`, `jan`). Bare values end at `,`, `}` or a newline.
- Values are stored verbatim, braces included. For display, braces are
  removed and runs of whitespace collapse to a single space.
- `@string` macros and `#` concatenation are not expanded.

Multi-entry text (from an import) is split into entries by brace-balancing
each `@type{…}` block. `@string`, `@preamble` and `@comment` blocks are
skipped. Each entry is filed under its citation key, sanitised into an ID as
in §1.1. An entry is skipped if that ID already exists, and refused if its DOI
matches a record already in the workspace.

### 2.1 Record types

The entry type maps to a display type, used for the "By Type" filter and
elsewhere:

| Entry type | Type |
| --- | --- |
| `article` | Journal article |
| `inproceedings`, `conference`, `proceedings` | Proceedings |
| `incollection` whose `booktitle` starts with "Proceedings of" | Proceedings |
| `inbook`, other `incollection` | Book chapter |
| `book` | Book |
| `online`, `electronic`, `webpage` | Webpage |
| anything else, including `misc` | Other |

### 2.2 Derived display fields

| Field | Source |
| --- | --- |
| Author | `author`, else `editor` |
| Year | `year` |
| Title | `title` |
| Outlet | `journal`, else `journaltitle`, else `booktitle` |
| DOI | `doi`, with any `http(s)://(dx.)doi.org/` prefix removed |

The Outlet column shows the outlet only for journal articles, book chapters
and proceedings, and an em dash (—) otherwise.

---

## 3. Notes (`markdown/<shard>/<id>.md`)

```
---
pdf: S/SmithJones2025.pdf
epub: /Users/me/Books/SmithJones2025.epub
my_works:
- project1
---
Free-form Markdown notes.
```

- The file is optional. It is created the first time notes are saved or a
  full-text file is linked.
- The frontmatter is a YAML mapping between two `---` lines at the very top
  of the file. Everything after the closing `---` line is the notes body,
  kept byte for byte.
- If the file has no frontmatter, the whole file is the body. If the
  frontmatter is not valid YAML, or is not a mapping, it is treated as empty.
- `pdf` and `epub` link the full text. A path is stored **relative to the
  full-text library folder** (a preference) when the file lies inside that
  folder, and as an absolute path otherwise. A record "has a PDF" or "has an
  EPUB" when the key is present and non-empty.
- Other keys are preserved. Every write re-emits the whole frontmatter, keys
  sorted, so a writer must read the current frontmatter, change what it needs,
  and write everything back.
- An empty frontmatter is written as `{}`, so a new notes file begins
  `---\n{}\n---\n`.

---

## 4. My Works (`my_works/*.yml`)

```
name: My Dissertation
cites:
- Jones2009_JAIS
- SmithJones2025_MISQ
published_as: SmithJones2025_MISQ
```

- The file stem is the work's key and can be anything. New works get a stem
  made from the name (as in §1.1), de-duplicated with `_2`, `_3`, and so on.
- `name` is the display name, falling back to the file stem. `cites` lists
  Bibliotheca IDs. `published_as` is optional and is the ID of the record for
  the published version of the work.
- On read, `title` is accepted for `name`, `citations` for `cites`, and
  `published_version` for `published_as`.
- **Canonical form**: keys in the order `name`, `cites`, `published_as`, with
  `cites` de-duplicated and sorted case-insensitively. Files are rewritten in
  canonical form when saved, and when loaded if they parse but are not
  canonical. The Mac app leaves a file that does not parse untouched.
- Renaming a record updates every `cites` entry and `published_as` that
  refers to it.

---

## 5. Authors (`authors/<SURNAME_GivenNames>.yml`)

```
given_names: Shoshana
id: ZUBOFF_Shoshana
starred: true
surname: Zuboff
```

Authors are derived from the Author field (§2.2) of every record each time a
workspace loads. A file is written, with keys sorted, the first time an author
is seen; after that only `starred` is user state.

- The author string is split on ` and `. Each name is either
  "Surname, Given Names" (split at the first comma) or "Given Names Surname"
  (the last word is the surname). Braces are removed first.
- **Author id**: the surname with every character outside `A–Z a–z 0–9`
  removed, upper-cased; then `_`; then the given names title-cased (a cased
  letter is upper-cased after an uncased character and lower-cased otherwise)
  with the same characters removed. With no given names the id is just the
  surname part. For example, "van der Berg, mary-jane" gives
  `VANDERBERG_MaryJane`.
- A record counts once per author, even if the author is listed twice.

---

## 6. Outlets (`outlets/<nickname-or-slug>.yml`)

```
name: Journal of Bibliotheca
nickname: JBIB
starred: true
jflags:
- A*
- FT50
```

Outlets are derived from the Outlet field (§2.2) of **journal articles and
proceedings only**; the book titles of book chapters never become outlets.

- An outlet's stable key is the **slug** of its full name: lower-case it,
  replace each run of characters outside `a–z 0–9` with `-`, and trim `-`
  from the ends. "Journal of Bibliotheca" becomes `journal-of-bibliotheca`.
  Records and outlet files are matched by this slug, never by file name.
- `name` is refreshed from the BibTeX. `nickname`, `starred` and `jflags` are
  user state and are preserved across loads.
- The file stem is the nickname when one is set (`JBIB.yml`), otherwise the
  slug (`journal-of-bibliotheca.yml`). Setting or clearing a nickname writes
  the new file first, then deletes the old one.
- A nickname contains only the letters `A–Z` and `a–z`, and must be unique
  across outlets, case-insensitively.
- `jflags` are free-form rating labels (for example ABDC `A*`, `FT50`). They
  are stored de-duplicated and sorted case-insensitively. For display, they
  are ordered by the user's configured priorities.
- Keys are written in the order `name`, `nickname` (only when set),
  `starred`, `jflags`.

---

## 7. YAML style

All YAML files are written in the style of PyYAML's
`safe_dump(..., allow_unicode=True)`, so files written by either edition are
identical:

- Block style throughout. Sequences inside a mapping are **not** indented
  (`cites:` followed by `- item` lines). An empty sequence is written `[]` and
  an empty mapping `{}`.
- Strings are written plain when that reads back as the same string.
- Otherwise they are single-quoted, with `'` doubled. That covers strings that
  look like numbers, booleans, null or dates (`'2025'`, `'yes'`), strings
  starting with an indicator character (`'*A'`), and strings containing `: `
  or ` #`.
- Strings with line breaks, tabs or unprintable characters are double-quoted
  with escapes.
- Booleans are `true` and `false`.

---

## 8. Validation

The Validate report flags, without changing anything:

- `.md` files with no matching `.bib`.
- Records whose BibTeX citation key differs from their ID.
- `pdf`/`epub` links pointing to missing files.
- `cites` and `published_as` entries pointing to unknown IDs.
- DOIs shared by more than one record.
- For journal articles and proceedings, disagreement between the ID suffix
  (the text after the last `_`) and the outlet's nickname:
  - a nickname is set but the ID has no suffix;
  - both exist but differ;
  - the ID has a suffix but the outlet has no nickname.
