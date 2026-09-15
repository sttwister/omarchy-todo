// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert")
const {
    ALL,
    categories,
    tabs,
    defaultCategory,
    categoryLabel,
    normalizeCategory,
    cycleCategory,
    parseTodos,
    sortTodos,
    serializeTodos,
    viewTodos,
    trim,
    countRemaining,
} = require("../Todos.js")

const FIRST = defaultCategory()

test("parseTodos reads a well-formed list", () => {
    const out = parseTodos('[{"title":"a","completed":false,"category":"Personal"},{"title":"b","completed":true,"category":"REBS"}]')
    assert.deepStrictEqual(out, [
        { title: "a", completed: false, category: "Personal" },
        { title: "b", completed: true, category: "REBS" },
    ])
})

test("parseTodos floats open tasks above completed ones", () => {
    const out = parseTodos('[{"title":"done","completed":true},{"title":"open","completed":false}]')
    assert.deepStrictEqual(out.map(t => t.title), ["open", "done"])
})

test("parseTodos preserves order within each group", () => {
    const raw = JSON.stringify([
        { title: "o1", completed: false },
        { title: "d1", completed: true },
        { title: "o2", completed: false },
        { title: "d2", completed: true },
    ])
    assert.deepStrictEqual(parseTodos(raw).map(t => t.title), ["o1", "o2", "d1", "d2"])
})

test("parseTodos trims titles and drops blank ones", () => {
    const out = parseTodos('[{"title":"  spaced  "},{"title":"   "},{"title":"kept"}]')
    assert.deepStrictEqual(out.map(t => t.title), ["spaced", "kept"])
})

test("parseTodos treats a missing completed flag as open", () => {
    assert.strictEqual(parseTodos('[{"title":"a"}]')[0].completed, false)
})

test("parseTodos only accepts a literal true as completed", () => {
    assert.strictEqual(parseTodos('[{"title":"a","completed":"true"}]')[0].completed, false)
    assert.strictEqual(parseTodos('[{"title":"a","completed":1}]')[0].completed, false)
})

test("parseTodos skips entries that are not shaped like todos", () => {
    const out = parseTodos('[null,42,"str",{"no":"title"},{"title":"ok"}]')
    assert.deepStrictEqual(out.map(t => t.title), ["ok"])
})

// A corrupt or absent state file must cost history, never the panel itself.
test("parseTodos degrades to an empty list rather than throwing", () => {
    assert.deepStrictEqual(parseTodos("not json"), [])
    assert.deepStrictEqual(parseTodos('{"not":"an array"}'), [])
    assert.deepStrictEqual(parseTodos(""), [])
    assert.deepStrictEqual(parseTodos(null), [])
    assert.deepStrictEqual(parseTodos(undefined), [])
})

// ---------------------------------------------------------------- categories

test("tabs put All in front of the categories", () => {
    assert.deepStrictEqual(tabs(), [ALL].concat(categories()))
})

test("All is a sentinel that cannot collide with a category name", () => {
    assert.strictEqual(ALL, "")
    assert.ok(!categories().includes(ALL))
    assert.strictEqual(categoryLabel(ALL), "All")
    assert.strictEqual(categoryLabel("Personal"), "Personal")
})

test("categories() hands out a copy callers cannot corrupt", () => {
    const list = categories()
    list.push("Injected")
    assert.ok(!categories().includes("Injected"))
})

test("normalizeCategory keeps a known category", () => {
    for (const name of categories())
        assert.strictEqual(normalizeCategory(name), name)
})

test("normalizeCategory matches case-insensitively and trims", () => {
    assert.strictEqual(normalizeCategory("  rebs RETRO "), "REBS retro")
    assert.strictEqual(normalizeCategory("personal"), "Personal")
})

// A file written before categories existed, or hand-edited to nonsense,
// still has to read as a valid list.
test("normalizeCategory falls back to the first category", () => {
    assert.strictEqual(normalizeCategory(undefined), FIRST)
    assert.strictEqual(normalizeCategory(null), FIRST)
    assert.strictEqual(normalizeCategory(""), FIRST)
    assert.strictEqual(normalizeCategory("Nonsense"), FIRST)
    assert.strictEqual(normalizeCategory(42), FIRST)
})

test("parseTodos gives pre-categories entries the first category", () => {
    assert.strictEqual(parseTodos('[{"title":"legacy"}]')[0].category, FIRST)
})

test("cycleCategory steps through the tabs and wraps both ways", () => {
    const list = tabs()
    assert.strictEqual(cycleCategory(ALL, 1), list[1])
    assert.strictEqual(cycleCategory(list[1], 1), list[2])
    assert.strictEqual(cycleCategory(list[list.length - 1], 1), ALL)
    assert.strictEqual(cycleCategory(ALL, -1), list[list.length - 1])
})

test("cycleCategory starts from All when the current tab is unknown", () => {
    assert.strictEqual(cycleCategory("Nonsense", 1), tabs()[1])
    assert.strictEqual(cycleCategory("Nonsense", -1), tabs()[tabs().length - 1])
})

const MIXED = parseTodos(JSON.stringify([
    { title: "r1", completed: false, category: "REBS" },
    { title: "p1", completed: false, category: "Personal" },
    { title: "rr1", completed: false, category: "REBS retro" },
    { title: "r2", completed: true, category: "REBS" },
    { title: "p2", completed: true, category: "Personal" },
]))

test("viewTodos on All returns every row in order", () => {
    assert.deepStrictEqual(viewTodos(MIXED, ALL).map(r => r.title), ["r1", "p1", "rr1", "r2", "p2"])
})

test("viewTodos on a category returns only that category", () => {
    assert.deepStrictEqual(viewTodos(MIXED, "REBS").map(r => r.title), ["r1", "r2"])
    assert.deepStrictEqual(viewTodos(MIXED, "Personal").map(r => r.title), ["p1", "p2"])
    assert.deepStrictEqual(viewTodos(MIXED, "REBS retro").map(r => r.title), ["rr1"])
})

// The overlay acts on the full list from a filtered selection, so each row
// has to say where it came from.
test("viewTodos carries the index into the full list", () => {
    assert.deepStrictEqual(viewTodos(MIXED, "REBS").map(r => r.sourceIndex), [0, 3])
    assert.deepStrictEqual(viewTodos(MIXED, ALL).map(r => r.sourceIndex), [0, 1, 2, 3, 4])
})

test("viewTodos keeps open tasks above completed ones within a tab", () => {
    assert.deepStrictEqual(viewTodos(MIXED, "REBS").map(r => r.completed), [false, true])
})

test("viewTodos of an empty category is empty, not everything", () => {
    const onlyRebs = parseTodos('[{"title":"a","category":"REBS"}]')
    assert.deepStrictEqual(viewTodos(onlyRebs, "Personal"), [])
})

test("countRemaining counts only open tasks", () => {
    assert.strictEqual(countRemaining([]), 0)
    assert.strictEqual(countRemaining([{ completed: false }, { completed: true }, { completed: false }]), 2)
})

test("countRemaining scopes to a category when given one", () => {
    assert.strictEqual(countRemaining(MIXED), 3)
    assert.strictEqual(countRemaining(MIXED, ALL), 3)
    assert.strictEqual(countRemaining(MIXED, "REBS"), 1)
    assert.strictEqual(countRemaining(MIXED, "REBS retro"), 1)
})

// ---------------------------------------------------------------- writing

test("serializeTodos round-trips through parseTodos", () => {
    const todos = [
        { title: "a", completed: false, category: "Personal" },
        { title: "b", completed: true, category: "REBS retro" },
    ]
    assert.deepStrictEqual(parseTodos(serializeTodos(todos)), todos)
})

test("serializeTodos writes pretty JSON with a trailing newline", () => {
    const text = serializeTodos([{ title: "a", completed: false, category: "REBS" }])
    assert.ok(text.endsWith("\n"))
    assert.ok(text.includes("\n  "))
})

test("serializeTodos keeps only the three persisted fields", () => {
    const text = serializeTodos([{ title: "a", completed: false, category: "REBS", extra: "dropped" }])
    assert.ok(!text.includes("extra"))
    assert.ok(text.includes('"category"'))
})

test("serializeTodos normalizes a category it was handed", () => {
    const text = serializeTodos([{ title: "a", completed: false }])
    assert.strictEqual(JSON.parse(text)[0].category, FIRST)
})

test("sortTodos is stable for an already-sorted list", () => {
    const todos = [{ title: "o", completed: false }, { title: "d", completed: true }]
    assert.deepStrictEqual(sortTodos(todos), todos)
})

// A tab is a lens, not a reordering: sorting must not group by category.
test("sortTodos leaves categories interleaved", () => {
    assert.deepStrictEqual(viewTodos(MIXED, ALL).map(r => r.category),
        ["REBS", "Personal", "REBS retro", "REBS", "Personal"])
})

test("trim strips surrounding whitespace", () => {
    assert.strictEqual(trim("  a  "), "a")
    assert.strictEqual(trim("\t\na\n"), "a")
    assert.strictEqual(trim("   "), "")
})
