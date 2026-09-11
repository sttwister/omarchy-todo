import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Todos.js" as Todos

// Bar companion to the overlay: how many tasks are still open, and a click
// target to open the list. The bar builds one instance per monitor, so this
// reads the state file itself rather than reaching for the overlay — the
// overlay is a single instance that may not be loaded on this screen, and a
// watched file keeps every bar in step for free.
BarWidget {
    id: root
    moduleName: "sttwister.todo"

    property int remaining: 0
    property int total: 0

    readonly property string todoPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/sttwister.todo.json"

    // A vertical bar has no room for "icon + count", so the count alone
    // carries the meaning there and the glyph stands in for an empty list.
    readonly property string label: {
        if (root.remaining <= 0)
            return "󰄱"
        return root.vertical ? String(root.remaining) : "󰄱 " + root.remaining
    }

    readonly property string tooltip: {
        if (root.total === 0)
            return "No tasks"
        if (root.remaining === 0)
            return "All tasks done"
        return root.remaining + (root.remaining === 1 ? " task remaining" : " tasks remaining")
    }

    function recount(raw) {
        var todos = Todos.parseTodos(raw)
        root.total = todos.length
        root.remaining = Todos.countRemaining(todos)
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    FileView {
        id: todoFile
        path: root.todoPath
        watchChanges: true
        printErrors: false
        onLoaded: root.recount(text())
        onLoadFailed: root.recount("[]")
        onFileChanged: reload()
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.label
        fontSize: Style.font.caption
        tooltipText: root.tooltip
        // Nothing outstanding is still worth a click target, just a quieter one.
        dimmed: root.remaining === 0

        onPressed: function (mouseButton) {
            if (root.bar)
                root.bar.run("omarchy-shell shell toggle sttwister.todo")
        }
    }
}
