// Pure helpers for the todo list. Kept free of QML types so they can be
// exercised by plain `node` tests.

// The categories a task can belong to. Fixed for now — the overlay builds
// its tabs from this list, so adding one here is the only edit needed.
var CATEGORIES = ["REBS", "Personal", "REBS retro"]

// Sentinel for the "All" tab. Empty rather than a label, so it can never
// collide with a real category name.
var ALL = ""

function categories() {
    return CATEGORIES.slice()
}

// Tab order: All first, then the categories in declaration order.
function tabs() {
    return [ALL].concat(CATEGORIES)
}

// Where a task lands when the category is not otherwise decided — an
// unrecognized name on disk, or adding while the All tab is selected.
function defaultCategory() {
    return CATEGORIES[0]
}

function categoryLabel(category) {
    return category === ALL ? "All" : category
}

// Anything that is not a known category collapses to the default, so a
// hand-edited or pre-categories file still reads as a valid list. Matching
// is case-insensitive to be forgiving of external edits.
function normalizeCategory(value) {
    var name = trim(value === undefined || value === null ? "" : value)
    var i
    for (i = 0; i < CATEGORIES.length; ++i)
        if (CATEGORIES[i] === name)
            return CATEGORIES[i]
    var lower = name.toLowerCase()
    for (i = 0; i < CATEGORIES.length; ++i)
        if (CATEGORIES[i].toLowerCase() === lower)
            return CATEGORIES[i]
    return defaultCategory()
}

// Step through the tabs with wraparound. `current` may be any string; an
// unknown one starts from All so an arrow key always lands somewhere sane.
function cycleCategory(current, delta) {
    var list = tabs()
    var at = list.indexOf(current)
    if (at < 0)
        at = 0
    var next = (at + delta) % list.length
    if (next < 0)
        next += list.length
    return list[next]
}

// Normalize whatever is on disk into a list of {title, completed, category}.
// Anything unparseable degrades to an empty list rather than throwing: a
// corrupt state file should cost the user their history, not the ability to
// open the panel.
function parseTodos(raw) {
    var todos = []
    var parsed
    try {
        parsed = JSON.parse(String(raw || "[]"))
    } catch (e) {
        return todos
    }
    if (!Array.isArray(parsed))
        return todos

    for (var i = 0; i < parsed.length; ++i) {
        var item = parsed[i]
        if (!item || typeof item.title !== "string")
            continue
        var title = trim(item.title)
        if (title === "")
            continue
        todos.push({
            title: title,
            completed: item.completed === true,
            category: normalizeCategory(item.category)
        })
    }
    return sortTodos(todos)
}

// Open tasks first, order preserved within each group. Categories do not
// reorder anything: the list stays one sequence and a tab only hides part
// of it, so a task keeps its place when the filter changes.
function sortTodos(todos) {
    var open = []
    var done = []
    for (var i = 0; i < todos.length; ++i)
        (todos[i].completed ? done : open).push(todos[i])
    return open.concat(done)
}

function serializeTodos(todos) {
    var out = []
    for (var i = 0; i < todos.length; ++i)
        out.push({
            title: todos[i].title,
            completed: todos[i].completed === true,
            category: normalizeCategory(todos[i].category)
        })
    return JSON.stringify(out, null, 2) + "\n"
}

// The rows one tab shows, each carrying the index it came from so the
// overlay can act on the full list from a filtered selection.
function viewTodos(todos, category) {
    var out = []
    for (var i = 0; i < todos.length; ++i) {
        if (category !== ALL && normalizeCategory(todos[i].category) !== category)
            continue
        out.push({
            sourceIndex: i,
            title: todos[i].title,
            completed: todos[i].completed === true,
            category: normalizeCategory(todos[i].category)
        })
    }
    return out
}

function trim(value) {
    return String(value).replace(/^\s+|\s+$/g, "")
}

// Open tasks, across everything or within one category.
function countRemaining(todos, category) {
    var want = category === undefined ? ALL : category
    var n = 0
    for (var i = 0; i < todos.length; ++i) {
        if (todos[i].completed)
            continue
        if (want !== ALL && normalizeCategory(todos[i].category) !== want)
            continue
        n++
    }
    return n
}

if (typeof module !== "undefined")
    module.exports = {
        ALL: ALL,
        categories: categories,
        tabs: tabs,
        defaultCategory: defaultCategory,
        categoryLabel: categoryLabel,
        normalizeCategory: normalizeCategory,
        cycleCategory: cycleCategory,
        parseTodos: parseTodos,
        sortTodos: sortTodos,
        serializeTodos: serializeTodos,
        viewTodos: viewTodos,
        trim: trim,
        countRemaining: countRemaining
    }
