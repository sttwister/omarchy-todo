// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert")
const { parseTodos, sortTodos, serializeTodos, trim, countRemaining } = require("../Todos.js")

test("parseTodos reads a well-formed list", () => {
    const out = parseTodos('[{"title":"a","completed":false},{"title":"b","completed":true}]')
    assert.deepStrictEqual(out, [
        { title: "a", completed: false },
        { title: "b", completed: true },
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

test("serializeTodos round-trips through parseTodos", () => {
    const todos = [{ title: "a", completed: false }, { title: "b", completed: true }]
    assert.deepStrictEqual(parseTodos(serializeTodos(todos)), todos)
})

test("serializeTodos writes pretty JSON with a trailing newline", () => {
    const text = serializeTodos([{ title: "a", completed: false }])
    assert.ok(text.endsWith("\n"))
    assert.ok(text.includes("\n  "))
})

test("serializeTodos keeps only the two persisted fields", () => {
    const text = serializeTodos([{ title: "a", completed: false, extra: "dropped" }])
    assert.ok(!text.includes("extra"))
})

test("sortTodos is stable for an already-sorted list", () => {
    const todos = [{ title: "o", completed: false }, { title: "d", completed: true }]
    assert.deepStrictEqual(sortTodos(todos), todos)
})

test("countRemaining counts only open tasks", () => {
    assert.strictEqual(countRemaining([]), 0)
    assert.strictEqual(countRemaining([{ completed: false }, { completed: true }, { completed: false }]), 2)
})

test("trim strips surrounding whitespace", () => {
    assert.strictEqual(trim("  a  "), "a")
    assert.strictEqual(trim("\t\na\n"), "a")
    assert.strictEqual(trim("   "), "")
})
