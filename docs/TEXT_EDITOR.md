# Player-facing text editor

The editor's Text view reads production Zig source under the project's `src` directory.
Browse by feature, then by the skill, item, screen or source owner. Passages identify their
purpose, such as Name, Description, Flavor or Tooltip, before showing the wording. The
inspector keeps the owner, purpose, exact source declaration and file/line visible above
the draft. Search matches wording, feature, owner, purpose and source identifiers. Clear
the query or return to All features to broaden the results. Each list scrolls independently.

Selecting a passage focuses its wording; selecting the search field focuses filtering.
The editing text is 24px, with 20px supporting labels. The Written by controls set an
authorship tag: Unknown, You, AI or Mixed. Existing text starts Unknown unless a matching saved tag exists.
Edits default to You; the tag is an attribution choice, not an automatic authorship detector.

Saving replaces that one quoted literal in its source file. Other bytes, including UTF-8
encoding, an existing BOM and line endings, stay intact. Rebuild the game to see the change
in play. Text editing does not change the open map or its undo history.

Before writing, the catalog compares the entire current file with the version it loaded.
If another editor changed it, reload the catalog before editing again. Source files use the
project's temporary-sibling-and-rename write path. Tags are stored separately in
`text-tags.json` at the project root. If the source saves but its tag file cannot be written,
the editor reports that separately; the source edit has still succeeded.

Tags match the source path, the literal's position in the token stream and its decoded
content. Unrelated code movement can therefore make an old attribution Unknown instead of
assigning it to a different passage. There is no persistent revision history. The current
draft supports undo/redo, selection, clipboard editing and navigation through wrapped lines.

The catalog uses Zig's tokenizer to omit test bodies, imports, reflection arguments,
console diagnostics, shaders and asset paths. It discovers text throughout gameplay,
skills, items, UI, editor and map display modules, including pieces concatenated into a
larger sentence. Display-looking literals are selected by their surrounding names and
content, so this is source discovery rather than a translation database. Small punctuation
fragments and generated/computed strings are not independently editable passages.
Context comes from enclosing source declarations, functions, named table rows and skill
registrations. When a runtime use cannot be determined, the browser shows the source owner
and call instead of claiming a particular screen. A literal reused in several places still
edits that shared source. Level-up text and fright speech are included under Effects.
Named nodes in `maps/**/*.map` are listed with their map-file provenance. They are read-only
here: use the map editor's existing Rename action so its open map and undo state remain
authoritative.

Enums used by display helpers can have editable display aliases. These save to
`assets/player-labels.txt`, keyed by the full enum type and field; their declaration stays
the source provenance. The aliases are embedded at rebuild and change captions without
renaming code or changing save identities. Default generated casing follows `menu.named`;
title and sentence uses can have different default casing. An explicit alias uses the exact
chosen text in each of those contexts. Internal, anonymous and explicitly overridden enum
labels remain read-only, as do input glyph identifiers and the name-entry keyboard.
Changing only an authorship tag does not create or alter a display alias.
`core/wording.zig` owns the shared alias format, display helpers and registration of editable
enum labels, including their default casing and excluded fields.

Editable text is nonempty ASCII, up to 4096 bytes, matching the game's text rendering
contract. Item flavor lines retain their source-defined 32-character limit. Display aliases
are single-line text. Quotes, backslashes and newlines are escaped safely. Format placeholders such as
`{s}` and `{d}`, escaped braces and inline control glyph markers must remain unchanged and
in the same order. Layout remains the author's responsibility; long replacements can need
an in-game layout check after rebuilding.

The tag file is also checked for changes made since loading. A malformed tag file produces
a warning and is preserved: source edits can still save, but attribution cannot be updated
until that file is repaired. Unknown tags are never inferred from existing prose.
