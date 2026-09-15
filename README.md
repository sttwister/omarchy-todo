# Todo

A centered, keyboard-driven todo overlay for [Omarchy](https://omarchy.org/).

One keybinding opens a card in the middle of the focused monitor with the
input already focused, so the same key both captures a task and reviews the
list. Tasks are filed under a category and the arrow keys walk the tabs.
Escape puts it away. An optional bar widget keeps the number of open tasks
in view and opens the same overlay on click.

![Todo overlay](preview.png)

## Why an overlay and not a bar widget

Bar widgets drop their panel under the bar, in a corner. This plugin is a
layer-shell `overlay` instead, so it opens centered on whichever monitor
Hyprland currently has focused — a quick capture surface rather than
something you go to the corner of the screen to find.

## Install

```bash
omarchy plugin add https://github.com/sttwister/omarchy-todo.git --enable --yes
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Todos", "omarchy-shell shell toggle sttwister.todo")
```

`--enable` also places the bar widget. To put it somewhere specific:

```bash
omarchy plugin enable sttwister.todo --after omarchy.workspaces
omarchy bar move sttwister.todo --section right     # once it is on the bar
```

## Keys

| Key | Action |
|-----|--------|
| type + `Enter` | add the task to the current category |
| `Enter` (empty input) | tick the selected task off |
| `↑` / `↓` | move the selection |
| `←` / `→` (empty input) | switch category tab |
| `Tab` / `Shift+Tab` | switch category tab, even while typing |
| `Ctrl+E` | rename the selected task in the input |
| `Ctrl+D` | delete the selected task |
| `Ctrl+L` | clear completed tasks in the current tab |
| `Esc` | cancel a rename → clear the input → close |

`←`/`→` only move between tabs when the input is empty; with text in it they
stay ordinary cursor keys, so a typo mid-task is still fixable. `Tab` and
`Shift+Tab` switch tabs either way.

Mouse works too: click a tab to select it, click a row to tick it,
right-click to rename, and the trash icon on the selected or hovered row
deletes it.

Completed tasks sink to the bottom and open tasks float to the top, with
order preserved inside each group.

## Categories

Every task belongs to one category. The tabs are `All` plus each category,
and each tab shows how many of its tasks are still open:

- REBS
- Personal
- REBS retro

A tab is a lens over one list rather than a separate list: filtering hides
rows, it never reorders them, so a task keeps its place when you switch
tabs. `All` mixes the categories and labels each row with its own.

Adding a task files it under the selected tab. `All` has no category to
infer, so a task added there goes to the first one — REBS.

`Ctrl+L` is scoped the same way: on a category it clears only that
category's completed tasks, on `All` it clears them everywhere.

The list lives in `Todos.js`, so changing the categories is one edit:

```js
var CATEGORIES = ["REBS", "Personal", "REBS retro"]
```

## Bar widget

The widget shows a checkbox glyph plus the number of open tasks — just the
glyph, dimmed, when nothing is outstanding — and clicking it toggles the
overlay. It is optional: remove it from the bar layout and the overlay and
its keybinding carry on working.

The bar builds one widget instance per monitor, so each reads the state file
directly rather than querying the overlay. The file is watched, so every bar
updates together whether a task was added from the overlay, another monitor,
or an external edit.

## Storage

Tasks live in a plain JSON file, so they are easy to read, sync, or edit
by hand:

```
~/.local/state/omarchy/settings/sttwister.todo.json
```

```json
[
  { "title": "Check out pstack", "completed": false, "category": "REBS" }
]
```

The file is watched, so an external edit shows up in the overlay without a
restart. A corrupt file degrades to an empty list rather than blocking the
panel from opening, and a task whose category is missing or unrecognized —
anything written before categories existed — reads as the first category
instead of disappearing.

## Theming

The overlay borrows the `[menu]` tokens from the active Omarchy theme, so it
matches the Omarchy menu, clipboard, and emoji pickers automatically — no
per-plugin color configuration.

## Development

The plugin directory *is* the checkout, so edit in place.

```bash
node --test tests/                          # pure logic in Todos.js
omarchy plugin validate .                   # manifest against the schema
omarchy restart shell                       # pick up edited QML
omarchy-shell shell toggle sttwister.todo   # open it
```

### QML edits need a shell restart, not a rescan

`omarchy-shell shell rescanPlugins` is not enough. It re-runs the plugin
scan and logs `Local plugin changed, reloading: sttwister.todo`, but the
shell keeps executing the QML it compiled into `~/.cache/quickshell/qmlcache/`
the first time it loaded — so edits to `Overlay.qml`, `CountWidget.qml`, or
`Todos.js` stay invisible however many times it says it reloaded. This
plugin sets `keepLoaded: true`, which is the likely reason a rescan
re-instantiates the overlay from the cached unit rather than from source.

Use `omarchy restart shell` after any QML or JS edit. To confirm it took,
the cache units are rewritten on a successful restart, so the newest ones
should be stamped with the restart:

```bash
ls -lt ~/.cache/quickshell/qmlcache | head -5
```

Timestamps older than the restart mean the shell is still running the old
bytecode.

Nothing in `Todos.js` depends on the shell, so `node --test tests/` passes
whether or not the running overlay has picked the changes up — green tests
are not evidence that what is on screen is current.

| File | Role |
|------|------|
| `manifest.json` | plugin id, kinds (`overlay`, `bar-widget`), entry points |
| `Overlay.qml` | the panel: surface, monitor routing, keys, tabs, list |
| `CountWidget.qml` | the bar widget: open-task count, click to toggle the overlay |
| `Todos.js` | categories, parsing, filtering, sorting, serializing — no QML types, so `node` can test it |

## License

MIT
