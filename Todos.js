// Pure helpers for the todo list. Kept free of QML types so they can be
// exercised by plain `node` tests.

// Normalize whatever is on disk into a list of {title, completed}. Anything
// unparseable degrades to an empty list rather than throwing: a corrupt state
// file should cost the user their history, not the ability to open the panel.
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
            completed: item.completed === true
        })
    }
    return sortTodos(todos)
}

// Open tasks first, order preserved within each group.
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
        out.push({ title: todos[i].title, completed: todos[i].completed === true })
    return JSON.stringify(out, null, 2) + "\n"
}

function trim(value) {
    return String(value).replace(/^\s+|\s+$/g, "")
}

function countRemaining(todos) {
    var n = 0
    for (var i = 0; i < todos.length; ++i)
        if (!todos[i].completed)
            n++
    return n
}

if (typeof module !== "undefined")
    module.exports = { parseTodos: parseTodos, sortTodos: sortTodos, serializeTodos: serializeTodos, trim: trim, countRemaining: countRemaining }
