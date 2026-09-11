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

    // Row the keyboard acts on. -1 while the list is empty.
    property int selectedIndex: 0
    // Row being renamed through the shared input, or -1 when the input is
    // composing a new task.
    property int editingIndex: -1

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
    // Chrome is header + input + rules + footer; whatever is left of the
    // screen after that is how far the list may grow before it scrolls.
    readonly property int maxListHeight: Math.max(rowHeight * 3,
        panel.height - Style.gapsOut * 2 - Style.space(210))

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

    function snapshot() {
        var todos = []
        for (var i = 0; i < todoModel.count; ++i) {
            var item = todoModel.get(i)
            todos.push({ title: item.title, completed: item.completed })
        }
        return todos
    }

    function loadTodos(raw) {
        var todos = Todos.parseTodos(raw)
        todoModel.clear()
        for (var i = 0; i < todos.length; ++i)
            todoModel.append(todos[i])
        root.remaining = Todos.countRemaining(todos)
        root.clampSelection()
    }

    function save() {
        todoFile.setText(Todos.serializeTodos(root.snapshot()))
        root.remaining = Todos.countRemaining(root.snapshot())
    }

    function clampSelection() {
        if (todoModel.count === 0)
            root.selectedIndex = -1
        else if (root.selectedIndex < 0)
            root.selectedIndex = 0
        else if (root.selectedIndex >= todoModel.count)
            root.selectedIndex = todoModel.count - 1
    }

    // ------------------------------------------------------------ actions

    function addTodo(text) {
        var title = Todos.trim(text)
        if (title === "")
            return false
        todoModel.insert(0, { title: title, completed: false })
        root.selectedIndex = 0
        root.save()
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

    function renameTodo(index, text) {
        var title = Todos.trim(text)
        root.editingIndex = -1
        input.clear()
        if (index < 0 || index >= todoModel.count)
            return
        if (title === "" || title === todoModel.get(index).title)
            return
        todoModel.setProperty(index, "title", title)
        root.save()
    }

    function startEdit(index) {
        if (index < 0 || index >= todoModel.count)
            return
        root.selectedIndex = index
        root.editingIndex = index
        input.text = todoModel.get(index).title
        input.forceActiveFocus()
        input.selectAll()
    }

    function cancelEdit() {
        root.editingIndex = -1
        input.clear()
    }

    function toggleTodo(index) {
        if (index < 0 || index >= todoModel.count)
            return
        var completed = !todoModel.get(index).completed
        todoModel.setProperty(index, "completed", completed)
        // Completed rows sink, reopened rows float, order preserved within
        // each group — the same shape parseTodos() enforces on load.
        var target = completed ? todoModel.count - 1 : 0
        todoModel.move(index, target, 1)
        root.selectedIndex = target
        root.save()
    }

    function removeTodo(index) {
        if (index < 0 || index >= todoModel.count)
            return
        if (root.editingIndex === index)
            root.cancelEdit()
        todoModel.remove(index)
        root.clampSelection()
        root.save()
    }

    function clearCompleted() {
        var removed = false
        for (var i = todoModel.count - 1; i >= 0; --i) {
            if (todoModel.get(i).completed) {
                todoModel.remove(i)
                removed = true
            }
        }
        if (!removed)
            return
        root.cancelEdit()
        root.clampSelection()
        root.save()
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

                // -------------------------------------------------- input
                TextField {
                    id: input
                    width: parent.width
                    placeholderText: root.editingIndex >= 0 ? "Rename task…" : "Add a task…"
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily

                    Keys.onPressed: function (event) {
                        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

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
                            anchors.right: trash.left
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
                    text: "Nothing to do"
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
                            : "enter add/tick · ↑↓ select · ^e edit · ^d delete · esc close"
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
