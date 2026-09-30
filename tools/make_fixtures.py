#!/usr/bin/env python3
"""Regenerate the parity fixtures from the Python/GTK edition of the app.

This is an optional maintenance tool. The Swift tests read the committed
Tests/BibliothecaCoreTests/Fixtures/parity.json and need nothing else; run
this script only when you want to re-check the Swift port against a newer
version of the Python reference implementation.

It runs the Python edition's pure core (the `qdvc` package) over a set of
sample inputs and writes the results to parity.json. The Python edition uses
bibtexparser when it is installed; this port always uses (a port of) the
fallback parser, so the fixtures are generated with `parse_bib_fallback`.

Usage:

    python3 tools/make_fixtures.py --python-repo /path/to/qdvc-bibliotheca

The path is a checkout of https://github.com/qdvc-apps/qdvc-bibliotheca (the
folder that contains the `qdvc` package). The QDVC_PYTHON_REPO environment
variable can be used instead of the option. Requires PyYAML.
"""

import argparse
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / "Tests" / "BibliothecaCoreTests" / "Fixtures" / "parity.json"


def _import_reference(python_repo: Path):
    """Import the reference modules from the given checkout."""
    if not (python_repo / "qdvc" / "__init__.py").is_file():
        sys.exit(f"error: {python_repo} does not contain the qdvc package")
    sys.path.insert(0, str(python_repo))
    global yaml, builtin, acis, apa, naming, parse_bib_fallback, split_bib_entries
    global count_label, order_jflags, frontmatter_re
    import yaml  # noqa: F401
    from qdvc import builtin, builtin_acis as acis, builtin_apa7 as apa  # noqa: F401
    from qdvc import naming  # noqa: F401
    from qdvc.bibtex import parse_bib_fallback, split_bib_entries  # noqa: F401
    from qdvc.catalogue_sort import count_label, order_jflags  # noqa: F401
    from qdvc.markdown_io import _FRONTMATTER_RE as frontmatter_re  # noqa: F401


BIB_SAMPLES = {
    "article_doi_url": """@article{SmithJones2025_JBIB,
  author = {Smith, John Andrew and Jones, Beatrice},
  title = {{Knowledge Work} in the Age of Agents},
  journal = {Journal of Bibliotheca},
  year = {2025},
  volume = {12},
  number = {3},
  pages = {101--120},
  doi = {https://doi.org/10.1234/JBIB.2025.003}
}
""",
    "article_three_authors_no_pages": """@Article{Thompson2026,
  author = "Thompson, Ann and Lee, Bo and O'Brien, Ciara",
  title = "Why 'Trust' Matters: A & B",
  journaltitle = {MIS Quarterly},
  year = 2026,
  volume = 50,
  doi = {10.25300/MISQ/2026/1}
}
""",
    "article_given_first_names": """@article{Muller2019,
  author = {J\\"urgen M{\\"u}ller and Mary-Jane van der Berg},
  title = {Sociomateriality Revisited},
  journal = {Information Systems Journal},
  year = {2019},
  pages = {1-20}
}
""",
    "article_no_volume_no_doi": """@article{Solo2020,
  author = {Solo, Han},
  title = {Smuggling as Information Systems},
  journal = {Kessel Run Review},
  year = {2020}
}
""",
    "inproceedings": """@inproceedings{Chen2024_ICIS,
  author = {Chen, Wei and Patel, Ravi Kumar},
  title = {Digital Twins for Public Health},
  booktitle = {Proceedings of the 45th International Conference on Information Systems},
  address = {Bangkok, Thailand},
  pages = {1--15},
  year = {2024},
  doi = {10.5555/icis.2024.7}
}
""",
    "incollection_proceedings_of": """@incollection{Garcia2023,
  author = {Garcia, Lucia},
  title = {Platform Governance},
  booktitle = {Proceedings of the Australasian Conference on Information Systems},
  year = {2023}
}
""",
    "incollection_chapter": """@incollection{Walsham1995,
  author = {Walsham, Geoff},
  title = {Interpretive Case Studies in IS Research},
  booktitle = {Information Systems Research: Contemporary Approaches},
  editor = {Mumford, Enid and Hirschheim, Rudy},
  pages = {23--45},
  publisher = {North-Holland},
  address = {Amsterdam},
  year = {1995}
}
""",
    "book": """@book{Zuboff2019,
  author = {Zuboff, Shoshana},
  title = {The Age of Surveillance Capitalism},
  edition = {2nd},
  publisher = {PublicAffairs},
  address = {New York},
  year = {2019}
}
""",
    "book_editor_only": """@book{Edited2018,
  editor = {Orlikowski, Wanda J.},
  title = {Edited Volume on Practice},
  publisher = {Oxford University Press},
  date = {2018-05-01}
}
""",
    "online": """@online{ACIS2026Site,
  author = {{Association for Information Systems}},
  title = {ACIS 2026 Call for Papers},
  url = {https://acis2026.example.org/cfp},
  urldate = {2026-07-10},
  organization = {AIS},
  year = {2026}
}
""",
    "misc_no_author_no_year": """@misc{Anon,
  title = {An Untitled Working Paper},
  howpublished = {Mimeo}
}
""",
    "crlf_line_endings": "@article{CRLF2021,\r\n  author = {Doe, Jane},\r\n  title = {Windows Line Endings},\r\n  journal = {Journal of Portability},\r\n  year = {2021}\r\n}\r\n",
    "many_authors": "@article{Big2022,\n  author = {" + " and ".join(
        f"Author{i}, A." for i in range(1, 23)) + "},\n  title = {Big Science},\n  journal = {Nature},\n  year = {2022}\n}\n",
    "unbalanced_and_bare": """@article{Bare2010,
  author = {Bare, Value},
  year = 2010,
  month = jan,
  title = {Unclosed {brace
""",
}

SPLIT_SAMPLES = [
    """% a comment line
@string{jbib = "Journal of Bibliotheca"}
@article{A2020, title = {One {Nested} Title}, year = {2020}}
@preamble{"\\newcommand{\\noop}[1]{}"}
@book{B2021,
  title = {Two},
  year = {2021}
}
@comment{ignored}
@misc{ C2022 , title={Three}}
""",
    "no entries here, just text with an @ sign",
    "@article{NoComma}",
]

NAMING_INPUTS = [
    "", "  Smith Jones 2025 ", "Smith&Jones:2025/JBIB", "__weird--", "Ünïcödé Name", "A B\tC",
    "SmithJones2025_JBIB", "NoSuffix", "Trailing_", "Journal of Bibliotheca",
    "MIS Quarterly (MISQ)", "  --Proc. of ICIS--  ", "https://doi.org/10.1/ABC",
    "http://dx.doi.org/10.2/x", "HTTPS://DOI.ORG/10.3/y", " 10.4/z ",
]

AUTHOR_ID_INPUTS = [
    ["Zuboff", "Shoshana"], ["van der Berg", "mary-jane"], ["O'Brien", "ciara"],
    ["", "Nobody"], ["Smith", ""], ["M\u00fcller", "J\u00fcrgen"], ["!!!", "X"],
    ["Lee", "bo 1st"],
]

NICKNAMES = ["JBIB", "misq", "ISJ2", "", "J BIB", "J-BIB", "\u00c9cole"]

YAML_SCALARS = [
    "hello", "FT50", "A*", "*A", "2025", "10.1234/abc", "yes", "No", "null", "", "a: b",
    "a:b", "x #y", "x#y", "#x", "- x", "S/Smith2025.pdf", "/Users/me/My Papers/x.pdf",
    "O'Brien", "'q'", '"dq"', "M\u00fcller", "trailing ", " leading", "1.5", ".5",
    "0x1F", "2024-01-01", "---x", "...x", "a\tb", "~", "on", "Journal of Bibliotheca",
    "Proceedings of the 45th ICIS", "?x", ":x", "@x", "%x", "!x", "&x", "|x", ">x", "x:",
    "1_000", "+1", "-1", "07", "1:30", ".inf", ".NaN", "a,b", "[x]", "x]", "{a}", "=", "<<",
]

YAML_DOCUMENTS = [
    {"sort_keys": False, "data": [["name", "My Dissertation"], ["cites", ["Jones2009_JAIS", "SmithJones2025_MISQ"]]]},
    {"sort_keys": False, "data": [["name", "Empty"], ["cites", []]]},
    {"sort_keys": False, "data": [["name", "Journal of Bibliotheca"], ["nickname", "JBIB"], ["starred", True], ["jflags", ["A*", "FT50"]]]},
    {"sort_keys": True, "data": [["surname", "Zuboff"], ["id", "ZUBOFF_Shoshana"], ["starred", False], ["given_names", "Shoshana"]]},
    {"sort_keys": True, "data": [["pdf", "S/Smith2025.pdf"], ["my_works", ["project1"]], ["epub", "/abs/path/book.epub"]]},
    {"sort_keys": True, "data": []},
]

MARKDOWN_SAMPLES = [
    "---\npdf: S/Smith2025.pdf\nmy_works:\n- project1\n---\n# Notes\n\nBody text.\n",
    "No frontmatter at all.\n",
    "---\n{}\n---\n",
    "---\nnot: [valid\n---\nbody survives\n",
    "---\nepub: 'quoted.epub'\nstarred: true\n---\n\n",
]

DISAMBIGUATION_RECORDS = [
    {"bibliotheca_id": "Smith2025a", "author": "Smith, John", "year": "2025", "title": "Zeta study"},
    {"bibliotheca_id": "Smith2025b", "author": "Smith, J.", "year": "2025", "title": "Alpha study"},
    {"bibliotheca_id": "Smith2025c", "author": "Smith, Jane and Jones, B.", "year": "2025", "title": "Other"},
    {"bibliotheca_id": "Smith2024", "author": "Smith, John", "year": "2024", "title": "Solo"},
    {"bibliotheca_id": "NoYear1", "author": "Anon", "year": "", "title": "A"},
    {"bibliotheca_id": "NoYear2", "author": "Anon", "year": "", "title": "B"},
]


class _Rec:
    def __init__(self, d):
        self.__dict__.update(d)


def entry_json(e):
    fields = {k: v for k, v in e.items() if k not in ("ENTRYTYPE", "ID")}
    return {"entry_type": e.get("ENTRYTYPE"), "citation_key": e.get("ID"), "fields": fields}


def index_fields(e):
    return {
        "type_label": builtin.type_label(e.get("ENTRYTYPE") or "misc", e.get("booktitle")),
        "author": builtin.clean(e.get("author") or e.get("editor")),
        "year": builtin.clean(e.get("year")),
        "title": builtin.clean(e.get("title")),
        "journal": builtin.clean(e.get("journal") or e.get("journaltitle") or e.get("booktitle")),
        "doi": naming.normalise_doi(e.get("doi")),
    }


def yaml_scalar(value):
    text = yaml.safe_dump({"k": value}, allow_unicode=True)
    assert text.startswith("k: ") and text.endswith("\n"), text
    return text[3:-1]


def main():
    bib = []
    for name, text in BIB_SAMPLES.items():
        e = parse_bib_fallback(text)
        bib.append({
            "name": name,
            "text": text,
            "parsed": entry_json(e) if e else None,
            "index": index_fields(e) if e else None,
            "apa_markup": apa.format_apa_markup(e) if e else None,
            "apa_plain": apa.format_apa_plain(e) if e else None,
            "acis_markup": acis.format_acis_markup(e, "b") if e else None,
            "acis_plain": acis.format_acis_plain(e) if e else None,
            "acis_in_text": acis.in_text_plain(e, "a") if e else None,
            "acis_in_text_narrative": acis.in_text_plain(e, "", narrative=True) if e else None,
            "apa_author_list": apa.format_author_list(e.get("author", "")) if e else None,
            "acis_author_list": acis.format_author_list(e.get("author", "")) if e else None,
        })

    split = [{"text": t, "entries": [{"text": et, "key": k} for et, k in split_bib_entries(t)]}
             for t in SPLIT_SAMPLES]

    naming_cases = [{
        "input": s,
        "sanitise_id": naming.sanitise_id(s),
        "sanitise_stem": naming.sanitise_stem(s),
        "slugify_outlet": naming.slugify_outlet(s),
        "id_suffix": naming.id_suffix(s),
        "normalise_doi": naming.normalise_doi(s),
    } for s in NAMING_INPUTS]

    author_ids = [{"surname": s, "given": g, "expected": naming.make_author_id(s, g)}
                  for s, g in AUTHOR_ID_INPUTS]

    nicknames = [{"input": n, "valid": bool(naming._OUTLET_NICKNAME_RE.fullmatch(n))}
                 for n in NICKNAMES]

    name_splits = []
    for raw in ["Smith, John Andrew", "John Andrew Smith", "{Association for Information Systems}",
                "Plato", "de la Cruz, Juan", "  ", "Mary-Jane van der Berg"]:
        s, g = builtin.split_name(raw)
        name_splits.append({"input": raw, "surname": s, "given": g,
                            "surname_initials": builtin.surname_initials(raw)})

    yaml_scalars = [{"value": v, "expected": yaml_scalar(v)} for v in YAML_SCALARS]

    yaml_documents = []
    for doc in YAML_DOCUMENTS:
        data = {k: v for k, v in doc["data"]}
        yaml_documents.append({
            "sort_keys": doc["sort_keys"],
            "pairs": doc["data"],
            "expected": yaml.safe_dump(data, sort_keys=doc["sort_keys"], allow_unicode=True),
        })

    markdown = []
    for text in MARKDOWN_SAMPLES:
        m = frontmatter_re.match(text)
        if m:
            try:
                fm = yaml.safe_load(m.group(1)) or {}
            except yaml.YAMLError:
                fm = {}
            if not isinstance(fm, dict):
                fm = {}
            body = m.group(2)
        else:
            fm, body = {}, text
        markdown.append({"text": text, "keys": sorted(fm.keys()),
                         "strings": {k: v for k, v in fm.items() if isinstance(v, str)},
                         "body": body})

    disambiguation = {
        "records": DISAMBIGUATION_RECORDS,
        "expected": acis.disambiguator_map([_Rec(r) for r in DISAMBIGUATION_RECORDS]),
        "letters": {str(n): acis._letter(n) for n in (0, 1, 25, 26, 27, 51, 52, 701, 702)},
    }

    misc = {
        "count_labels": {str(n): count_label(n) for n in (0, 1, 42)},
        "order_jflags": {
            "flags": ["FT50", "A*", "ABDC-A", "zeta", "Alpha"],
            "priority": {"A*": 1, "FT50": 0.5},
            "expected": order_jflags(["FT50", "A*", "ABDC-A", "zeta", "Alpha"], {"A*": 1, "FT50": 0.5}),
        },
        "markup_to_plain": [
            {"input": m, "expected": builtin.markup_to_plain(m)}
            for m in ["<i>Title</i> &amp; more", "O&#x27;Brien &quot;q&quot; &lt;tag&gt;", "&amp;lt;"]
        ],
        "type_labels": [
            {"type": t, "booktitle": b, "expected": builtin.type_label(t, b)}
            for t, b in [("article", None), ("INPROCEEDINGS", None), ("incollection", "{Proceedings of} X"),
                         ("incollection", "Handbook"), ("thesis", None), ("", None), ("Online", None)]
        ],
    }

    fixtures = {
        "bib": bib, "split": split, "naming": naming_cases, "author_ids": author_ids,
        "nicknames": nicknames, "name_splits": name_splits, "yaml_scalars": yaml_scalars,
        "yaml_documents": yaml_documents, "markdown": markdown,
        "disambiguation": disambiguation, "misc": misc,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(fixtures, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(HERE)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--python-repo", type=Path,
                        default=os.environ.get("QDVC_PYTHON_REPO"),
                        help="checkout of the Python edition (contains qdvc/)")
    args = parser.parse_args()
    if not args.python_repo:
        parser.error("pass --python-repo or set QDVC_PYTHON_REPO")
    _import_reference(Path(args.python_repo).expanduser().resolve())
    main()
