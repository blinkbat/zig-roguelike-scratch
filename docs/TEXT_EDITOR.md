# Player-facing text editor

Open **Text** in the map editor. Browse by concern, text type and owner, or search wording, purpose and source identifiers. Select a passage to see its declaration and file location. Selecting **All text** and clearing the query restores the full list. The tree, passage list and draft scroll independently. Drafts support selection, clipboard editing, undo/redo and navigation across wrapped lines.

| Passage | Where a save goes |
| --- | --- |
| Quoted source text | The selected literal in `src/**/*.zig`. A shared literal changes every use. The catalog tokenizes production code and skips technical strings, test bodies, shaders and asset paths. |
| Registered enum caption | A single-line alias in `assets/data/player-labels.txt`. The chosen spelling applies in every display context. Input glyphs, the name-entry keyboard and unregistered or explicitly excluded enum fields are read-only. |
| Named map node | Read-only in Text. Use **Rename** in the map editor to include the change in map undo. |

[The wording registry](../src/core/wording.zig) owns eligible fields, default casing and alias keys. When moving a registered enum, set `saved_name` to its original name so existing aliases still resolve.

## Saving and attribution

Enter nonempty ASCII text up to 32,768 bytes. Preserve format arguments such as `{s}` and `{d}`, escaped braces and inline control glyphs in their original order. The editor escapes quotes, backslashes and line breaks when writing a source literal. Rebuild with `build.cmd` to apply source and alias changes. Inspect the affected layout if the wording grew.

The catalog checks the loaded source or alias file and the root `text-tags.json` for external changes before saving. Reload after a conflict. It replaces source files through a temporary sibling, preserving bytes outside the literal, including line endings and any BOM. Map undo operates independently.

**Written by** offers Unknown, You, AI and Mixed. Edits default to You. A tag-only change to an enum caption leaves the alias file alone. Tags match a source path, literal ordinal (or alias key hash) and decoded text hash. A mismatch displays Unknown. A malformed tag file is preserved. If attribution fails after a successful text save, the editor reports both outcomes.

## Map dialogue

Use **Dialog** for speech and replies in the open map. Speech holds 32,768 ASCII characters, replies 8,192 and speaker names 128. Enter inserts a paragraph break in speech or a reply. Escape leaves the field. Speech, replies and the line list scroll independently.

Single-line text uses `say` and `ask`. Multiline text uses `say_more |…` and `ask_more |…` records to preserve breaks and spaces. Maps have a 32 MiB serialized limit. The game and editor preview clip each line to one dialogue panel above the HUD. Chain lines with `then` when the full passage needs several panels.
