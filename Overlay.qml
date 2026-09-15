import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Todos.js" as Todos

// A centered, keyboard-first todo list. Unlike a bar popout this is a
// fullscreen layer-shell overlay, so it lands in the middle of whichever
// monitor Hyprland has focused rather than under a bar widget.
Item {
    id: root

    // Injected by the shell host for every plugin entry point.
    property var shell: null
    property var manifest: null

    readonly property string pluginId: (manifest && manifest.id) || "sttwister.todo"

    property bool opened: false
    property int remaining: 0

    // Row the keyboard acts on, as an index into the *filtered* list.
    // -1 while the current tab is empty.
    property int selectedIndex: 0
    // Row being renamed through the shared input, or -1 when the input is
    // composing a new task. Also a filtered index.
    property int editingIndex: -1

    // ---------------------------------------------------------- categories
    //
    // The whole list lives in `todos`; `todoModel` is the slice one tab
    // shows. Every action takes a filtered index and maps it back through
    // the row's sourceIndex, so the tab is purely a lens over one sequence.
    property var todos: []
    readonly property var tabList: Todos.tabs()
    property string activeCategory: Todos.ALL
    // Open-task count per tab, in tabList order. Recomputed by rebuild()
    // because a binding over a function call would never re-evaluate.
    property var tabCounts: []

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/settings"
    readonly property string todoPath: stateDir + "/sttwister.todo.json"

    // ------------------------------------------------------------ theming
    //
    // Shares the [menu] surface tokens, so a theme that styles the Omarchy
    // menu styles this overlay too.
    readonly property color background: Color.menu.background
    readonly property color foreground: Color.menu.text
    readonly property color scrim: Color.menu.scrim
    readonly property color selectedBackground: Color.menu.selectedBackground
    readonly property color accent: Color.accent
    readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    readonly property string fontFamily: Style.font.menuFamily

    readonly property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
    readonly property int rowHeight: Math.max(Style.space(34), Style.font.body + Style.spacing.controlPaddingY * 3)
    // Chrome is header + tabs + input + rules + footer; whatever is left of
    // the screen after that is how far the list may grow before it scrolls.
    readonly property int maxListHeight: Math.max(rowHeight * 3,
        panel.height - Style.gapsOut * 2 - Style.space(260))

    // --------------------------------------------------------- monitor
    //
    // Frozen at open time: moving focus to another output while the overlay
    // is up should not teleport the card mid-interaction.
    property var targetScreen: null

    function focusedScreen() {
        var monitor = Hyprland.focusedMonitor
        var name = monitor ? String(monitor.name || "") : ""
        if (!name)
            return null
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; ++i)
            if (String(screens[i].name) === name)
                return screens[i]
        return null
    }

    // ----------------------------------------------------- host contract

    function open(payloadJson) {
        root.targetScreen = root.focusedScreen()
        root.opened = true
        root.editingIndex = -1
        root.clampSelection()
        input.clear()
        Qt.callLater(function () {
            input.forceActiveFocus()
        })
    }

    function close() {
        root.opened = false
        root.editingIndex = -1
        input.clear()
    }

    // Closing on our own initiative has to tell the host, or its open-panel
    // bookkeeping keeps thinking we are up and the next toggle is a no-op.
    function dismiss() {
        root.close()
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId)
    }

    function toggle() {
        if (root.opened)
            root.dismiss()
        else
            root.open("{}")
    }

    // --------------------------------------------------------- model I/O

    ListModel {
        id: todoModel
    }

    function loadTodos(raw) {
        root.todos = Todos.parseTodos(raw)
        root.rebuild()
    }

    // Reproject `todos` through the active tab. Cheap enough to run on every
    // mutation, which keeps the filtered model from needing its own edits.
    function rebuild() {
        var rows = Todos.viewTodos(root.todos, root.activeCategory)
        todoModel.clear()
        for (var i = 0; i < rows.length; ++i)
            todoModel.append(rows[i])

        var counts = []
        for (var t = 0; t < root.tabList.length; ++t)
            counts.push(Todos.countRemaining(root.todos, root.tabList[t]))
        root.tabCounts = counts

        root.remaining = Todos.countRemaining(root.todos, root.activeCategory)
        root.clampSelection()
    }

    function save() {
        todoFile.setText(Todos.serializeTodos(root.todos))
    }

    function clampSelection() {
        if (todoModel.count === 0)
            root.selectedIndex = -1
        else if (root.selectedIndex < 0)
            root.selectedIndex = 0
        else if (root.selectedIndex >= todoModel.count)
            root.selectedIndex = todoModel.count - 1
    }

    // Filtered index of a row of the full list, or -1 when this tab hides it.
    function viewIndexOf(sourceIndex) {
        for (var i = 0; i < todoModel.count; ++i)
            if (todoModel.get(i).sourceIndex === sourceIndex)
                return i
        return -1
    }

    function sourceIndexOf(viewIndex) {
        if (viewIndex < 0 || viewIndex >= todoModel.count)
            return -1
        return todoModel.get(viewIndex).sourceIndex
    }

    // ----------------------------------------------------------- tabs

    function setCategory(category) {
        if (root.activeCategory === category)
            return
        root.cancelEdit()
        root.activeCategory = category
        root.selectedIndex = 0
        root.rebuild()
        todoList.positionViewAtBeginning()
    }

    function moveCategory(delta) {
        root.setCategory(Todos.cycleCategory(root.activeCategory, delta))
    }

    // ------------------------------------------------------------ actions

    function addTodo(text) {
        var title = Todos.trim(text)
        if (title === "")
            return false
        // On the All tab there is no tab to infer from, so a new task goes
        // to the first category rather than nowhere.
        var category = root.activeCategory === Todos.ALL ? Todos.defaultCategory()
                                                         : root.activeCategory
        var todos = root.todos.slice()
        todos.unshift({ title: title, completed: false, category: category })
        root.todos = todos
        root.save()
        root.rebuild()
        root.selectedIndex = root.viewIndexOf(0)
        return true
    }

    function commitInput() {
        if (root.editingIndex >= 0) {
            root.renameTodo(root.editingIndex, input.text)
            return
        }
        if (root.addTodo(input.text))
            input.clear()
    }

    function renameTodo(viewIndex, text) {
        var title = Todos.trim(text)
        var source = root.sourceIndexOf(viewIndex)
        root.editingIndex = -1
        input.clear()
        if (source < 0)
            return
        if (title === "" || title === root.todos[source].title)
            return
        var todos = root.todos.slice()
        todos[source] = { title: title, completed: todos[source].completed, category: todos[source].category }
        root.todos = todos
        root.save()
        root.rebuild()
    }

    function startEdit(viewIndex) {
        if (viewIndex < 0 || viewIndex >= todoModel.count)
            return
        root.selectedIndex = viewIndex
        root.editingIndex = viewIndex
        input.text = todoModel.get(viewIndex).title
        input.forceActiveFocus()
        input.selectAll()
    }

    function cancelEdit() {
        root.editingIndex = -1
        input.clear()
    }

    function toggleTodo(viewIndex) {
        var source = root.sourceIndexOf(viewIndex)
        if (source < 0)
            return
        var todos = root.todos.slice()
        var item = todos[source]
        var completed = !item.completed
        todos.splice(source, 1)
        // Completed rows sink, reopened rows float, order preserved within
        // each group — the same shape parseTodos() enforces on load.
        var target = completed ? todos.length : 0
        todos.splice(target, 0, { title: item.title, completed: completed, category: item.category })
        root.todos = todos
        root.save()
        root.rebuild()
        root.selectedIndex = root.viewIndexOf(target)
        root.clampSelection()
    }

    function removeTodo(viewIndex) {
        var source = root.sourceIndexOf(viewIndex)
        if (source < 0)
            return
        if (root.editingIndex === viewIndex)
            root.cancelEdit()
        var todos = root.todos.slice()
        todos.splice(source, 1)
        root.todos = todos
        root.save()
        root.rebuild()
    }

    // Scoped to the visible tab: on All this clears everything, on a
    // category it leaves the other categories' history alone.
    function clearCompleted() {
        var kept = []
        var removed = false
        for (var i = 0; i < root.todos.length; ++i) {
            var item = root.todos[i]
            var inTab = root.activeCategory === Todos.ALL || item.category === root.activeCategory
            if (inTab && item.completed) {
                removed = true
                continue
            }
            kept.push(item)
        }
        if (!removed)
            return
        root.cancelEdit()
        root.todos = kept
        root.save()
        root.rebuild()
    }

    function moveSelection(delta) {
        if (todoModel.count === 0)
            return
        var next = root.selectedIndex + delta
        if (next < 0)
            next = todoModel.count - 1
        else if (next >= todoModel.count)
            next = 0
        root.selectedIndex = next
        todoList.positionViewAtIndex(next, ListView.Contain)
    }

    // --------------------------------------------------------- persistence

    FileView {
        id: todoFile
        path: root.todoPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadTodos(text())
        onLoadFailed: root.loadTodos("[]")
        onFileChanged: reload()
    }

    Process {
        id: ensureDirsProc
        command: ["mkdir", "-p", root.stateDir]
        onExited: todoFile.reload()
    }

    Component.onCompleted: ensureDirsProc.running = true

    // ------------------------------------------------------------- surface

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: root.opened
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "sttwister-todo"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: root.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        BorderSurface {
            id: card
            anchors.centerIn: parent
            width: root.cardWidth
            height: content.implicitHeight + contentTopInset + contentBottomInset
            radius: Style.cornerRadius
            color: root.background
            borderSpec: root.borderSpec
            padding: Style.spacing.panelPadding

            // Clicks inside the card must not reach the dismiss layer.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {}
            }

            Column {
                id: content
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: card.contentTopInset
                    leftMargin: card.contentLeftInset
                    rightMargin: card.contentRightInset
                }
                spacing: Style.spacing.md

                // ------------------------------------------------- header
                Item {
                    width: parent.width
                    height: headerTitle.implicitHeight

                    Text {
                        id: headerTitle
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "TODO"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: todoModel.count === 0 ? ""
                            : root.remaining + " of " + todoModel.count + " remaining"
                        color: root.foreground
                        opacity: 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }

                // --------------------------------------------------- tabs
                //
                // A Flow rather than a Row so a long category list wraps on
                // a narrow card instead of running off the edge.
                Flow {
                    id: tabs
                    width: parent.width
                    spacing: Style.spacing.xs

                    Repeater {
                        model: root.tabList

                        Rectangle {
                            id: tab
                            required property int index
                            required property string modelData

                            readonly property bool active: root.activeCategory === tab.modelData
                            readonly property int openCount: index < root.tabCounts.length ? root.tabCounts[index] : 0

                            width: tabLabel.implicitWidth + Style.spacing.rowPaddingX * 2
                            height: Math.max(Style.space(26), tabLabel.implicitHeight + Style.spacing.controlPaddingY * 2)
                            radius: Style.cornerRadius
                            color: tab.active ? root.selectedBackground
                                : (tabArea.containsMouse ? Style.hoverFillFor(root.foreground, root.accent, Color.urgent)
                                                         : "transparent")

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: Todos.categoryLabel(tab.modelData)
                                    + (tab.openCount > 0 ? "  " + tab.openCount : "")
                                color: tab.active ? root.accent : root.foreground
                                opacity: tab.active ? 1 : (tabArea.containsMouse ? 0.9 : 0.55)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: tab.active
                            }

                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setCategory(tab.modelData)
                                    input.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------- input
                TextField {
                    id: input
                    width: parent.width
                    placeholderText: root.editingIndex >= 0
                        ? "Rename task…"
                        : (root.activeCategory === Todos.ALL
                            ? "Add a task to " + Todos.defaultCategory() + "…"
                            : "Add a task to " + root.activeCategory + "…")
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily

                    Keys.onPressed: function (event) {
                        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                        var shift = (event.modifiers & Qt.ShiftModifier) !== 0

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // An empty input means the keyboard is driving the
                            // list rather than composing, so Enter ticks the
                            // selected row off instead of adding nothing.
                            if (root.editingIndex < 0 && Todos.trim(input.text) === "")
                                root.toggleTodo(root.selectedIndex)
                            else
                                root.commitInput()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            if (root.editingIndex >= 0)
                                root.cancelEdit()
                            else if (input.text !== "")
                                input.clear()
                            else
                                root.dismiss()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab
                                   || (event.key === Qt.Key_Tab && shift)) {
                            root.moveCategory(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            root.moveCategory(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                            // ←/→ switch tabs only when there is nothing to
                            // put a cursor in; with text they stay ordinary
                            // cursor keys so typos are still fixable.
                            if (input.text === "") {
                                root.moveCategory(event.key === Qt.Key_Right ? 1 : -1)
                                event.accepted = true
                            }
                        } else if (ctrl && event.key === Qt.Key_E) {
                            root.startEdit(root.selectedIndex)
                            event.accepted = true
                        } else if (ctrl && event.key === Qt.Key_D) {
                            root.removeTodo(root.selectedIndex)
                            event.accepted = true
                        } else if (ctrl && event.key === Qt.Key_L) {
                            root.clearCompleted()
                            event.accepted = true
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Style.spacing.hairline
                    color: root.foreground
                    opacity: 0.12
                }

                // --------------------------------------------------- list
                ListView {
                    id: todoList
                    width: parent.width
                    height: Math.min(root.maxListHeight, contentHeight)
                    visible: todoModel.count > 0
                    model: todoModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string title
                        required property bool completed
                        required property string category

                        readonly property bool selected: root.selectedIndex === index

                        width: todoList.width
                        height: root.rowHeight
                        radius: Style.cornerRadius
                        color: selected ? root.selectedBackground
                            : (rowArea.containsMouse ? Style.hoverFillFor(root.foreground, root.accent, Color.urgent)
                                                     : "transparent")

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            anchors.rightMargin: trash.width + Style.spacing.md
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onContainsMouseChanged: if (containsMouse)
                                root.selectedIndex = row.index
                            onClicked: function (mouse) {
                                if (mouse.button === Qt.RightButton)
                                    root.startEdit(row.index)
                                else
                                    root.toggleTodo(row.index)
                            }
                        }

                        Text {
                            id: checkbox
                            anchors.left: parent.left
                            anchors.leftMargin: Style.spacing.rowPaddingX
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: row.completed ? "󰄲" : "󰄱"
                            color: row.completed ? root.accent : root.foreground
                            opacity: row.completed ? 1 : 0.7
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.icon
                        }

                        Text {
                            anchors.left: checkbox.right
                            anchors.leftMargin: Style.spacing.controlGap
                            anchors.right: categoryTag.left
                            anchors.rightMargin: Style.spacing.md
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: row.title
                            color: root.foreground
                            opacity: row.completed ? 0.45 : 1
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.strikeout: row.completed
                            elide: Text.ElideRight
                        }

                        // Only All mixes categories, so only All needs to say
                        // which one a row belongs to.
                        Text {
                            id: categoryTag
                            anchors.right: trash.left
                            anchors.rightMargin: visible ? Style.spacing.sm : 0
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.activeCategory === Todos.ALL
                            width: visible ? implicitWidth : 0
                            textFormat: Text.PlainText
                            text: row.category
                            color: root.foreground
                            opacity: row.completed ? 0.25 : 0.4
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        Rectangle {
                            id: trash
                            anchors.right: parent.right
                            anchors.rightMargin: Style.spacing.sm
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.rowHeight - Style.spacing.lg
                            height: width
                            radius: Style.cornerRadius
                            color: trashArea.containsMouse
                                ? Style.hoverFillFor(root.foreground, root.accent, Color.urgent)
                                : "transparent"
                            opacity: row.selected || rowArea.containsMouse || trashArea.containsMouse ? 1 : 0

                            Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "󰆴"
                                color: trashArea.containsMouse ? root.accent : root.foreground
                                opacity: trashArea.containsMouse ? 1 : 0.5
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.iconSmall
                            }

                            MouseArea {
                                id: trashArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeTodo(row.index)
                            }
                        }
                    }
                }

                Text {
                    visible: todoModel.count === 0
                    width: parent.width
                    height: root.rowHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: root.activeCategory === Todos.ALL
                        ? "Nothing to do"
                        : "Nothing in " + root.activeCategory
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.italic: true
                }

                // ------------------------------------------------- footer
                Item {
                    width: parent.width
                    height: hints.implicitHeight

                    Text {
                        id: hints
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.editingIndex >= 0
                            ? "enter rename · esc cancel"
                            : "enter add/tick · ↑↓ select · ←→ category · ^e edit · ^d delete · esc close"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Text {
                        id: clearCompleted
                        visible: root.remaining < todoModel.count
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "clear completed ^l"
                        color: clearArea.containsMouse ? root.accent : root.foreground
                        opacity: clearArea.containsMouse ? 1 : 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            anchors.margins: -Style.spacing.sm
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearCompleted()
                        }
                    }
                }
            }
        }
    }
}
