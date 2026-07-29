import QtQuick 2.15

FocusScope {
  id: keyboard
  property var userField: null
  property var passwordField: null
  property bool shifted: false
  property bool numMode: false
  property int selectedIndex: 0
  property int activeField: 1
  property int columns: 10
  property int gap: 6
  property int keyWidth: Math.min(100, Math.floor((width - (columns - 1) * gap) / columns))
  property int keyHeight: 48
  property var letterKeys: [
    "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
    "a", "s", "d", "f", "g", "h", "j", "k", "l", "⌫",
    "z", "x", "c", "v", "b", "n", "m", ".", "@", "⇧",
    "123", "-", "_", "SPACE", "/", "?", "!", ":", "CLEAR", "LOGIN"
  ]
  property var numberKeys: [
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "@", "#", "$", "%", "&", "*", "(", ")", "+", "⌫",
    "-", "_", "=", "/", "\\", ":", ";", ".", ",", "ABC",
    "ABC", "~", "^", "SPACE", "<", ">", "!", "?", "CLEAR", "LOGIN"
  ]
  property var keys: numMode ? numberKeys : letterKeys

  function label(index) {
    var value = keys[index]
    if (!numMode && shifted && value.length === 1 && value >= "a" && value <= "z") return value.toUpperCase()
    return value
  }

  function activeInput() {
    return activeField === 0 ? userField : passwordField
  }

  function append(value) {
    var input = activeInput()
    if (!input) return
    var position = input.cursorPosition
    input.text = input.text.slice(0, position) + value + input.text.slice(position)
    input.cursorPosition = position + value.length
  }

  function erase() {
    var input = activeInput()
    if (!input || input.cursorPosition === 0) return
    var position = input.cursorPosition
    input.text = input.text.slice(0, position - 1) + input.text.slice(position)
    input.cursorPosition = position - 1
  }

  function clear() {
    var input = activeInput()
    if (!input) return
    input.text = ""
    input.cursorPosition = 0
  }

  function submit() {
    if (userField && userField.text !== "" && passwordField && passwordField.text !== "") {
      var panel = passwordField
      while (panel && panel.user === undefined) panel = panel.parent
      if (panel) sddm.login(userField.text, passwordField.text, panel.session)
    }
  }

  function activate(index) {
    var value = keys[index]
    if (value === "⌫") erase()
    else if (value === "CLEAR") clear()
    else if (value === "LOGIN") submit()
    else if (value === "SPACE") append(" ")
    else if (value === "⇧") shifted = !shifted
    else if (value === "123") { numMode = true; shifted = false }
    else if (value === "ABC") numMode = false
    else append(label(index))
    forceActiveFocus()
  }

  function move(horizontal, vertical) {
    var row = Math.floor(selectedIndex / columns)
    var column = selectedIndex % columns
    row = (row + vertical + 4) % 4
    column = (column + horizontal + columns) % columns
    selectedIndex = row * columns + column
  }

  focus: true
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left) move(-1, 0)
    else if (event.key === Qt.Key_Right) move(1, 0)
    else if (event.key === Qt.Key_Up) move(0, -1)
    else if (event.key === Qt.Key_Down) move(0, 1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) activate(selectedIndex)
    else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Escape) { erase(); forceActiveFocus() }
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      activeField = activeField === 0 ? 1 : 0
      forceActiveFocus()
    }
    else if (event.key === Qt.Key_Home) {
      var input = activeInput()
      if (input) input.cursorPosition = 0
      forceActiveFocus()
    }
    else if (event.key === Qt.Key_End) {
      var inp = activeInput()
      if (inp) inp.cursorPosition = inp.text.length
      forceActiveFocus()
    }
    else if (event.text.length > 0 && !(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier)) { append(event.text); forceActiveFocus() }
    else return
    event.accepted = true
  }

  Grid {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 8
    columns: keyboard.columns
    spacing: keyboard.gap

    Repeater {
      model: keyboard.keys

      Rectangle {
        required property int index
        required property string modelData
        width: keyboard.keyWidth
        height: keyboard.keyHeight
        radius: 6
        color: index === keyboard.selectedIndex ? "#B4BEFE" : pointer.containsMouse ? "#45475A" : "#313244"
        border.color: index === keyboard.selectedIndex ? "#CDD6F4" : "#6C7086"
        border.width: index === keyboard.selectedIndex ? 2 : 1

        Text {
          anchors.centerIn: parent
          text: keyboard.label(index)
          color: index === keyboard.selectedIndex ? "#11111B" : "#CDD6F4"
          font.family: config.Font
          font.pointSize: modelData.length > 3 ? 9 : 12
          font.bold: true
        }

        MouseArea {
          id: pointer
          anchors.fill: parent
          hoverEnabled: true
          onEntered: keyboard.selectedIndex = index
          onClicked: {
            keyboard.selectedIndex = index
            keyboard.activate(index)
            keyboard.forceActiveFocus()
          }
        }
      }
    }
  }

  Component.onCompleted: forceActiveFocus()
}
