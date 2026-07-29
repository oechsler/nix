import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../assets"

Item {
  property var user: userField.text
  property var password: passwordField.text
  property var session: sessionPanel.session
  property var inputHeight: Screen.height * 0.032
  property var inputWidth: Screen.width * 0.16

  Column {
    id: powerPanel
    spacing: 8
    anchors {
      bottom: keyboardContainer.top
      left: parent.left
      bottomMargin: 8
    }
    PowerButton { id: powerButton }
    RebootButton { id: rebootButton }
    SleepButton { id: sleepButton }
    z: 5
  }

  Column {
    spacing: 8
    anchors {
      bottom: keyboardContainer.top
      right: parent.right
      bottomMargin: 8
    }
    SessionPanel { id: sessionPanel }
    z: 5
  }

  Column {
    spacing: 6
    z: 5
    width: inputWidth
    anchors {
      verticalCenter: parent.verticalCenter
      horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      visible: config.UserIcon == "true" ? true : false
      width: inputHeight * 5.7 ; height: inputHeight * 5.7
      color: "transparent"
      Image {
        source: Qt.resolvedUrl("../assets/defaultIcon.png")
        height: parent.width ; width: parent.width
      }
      Image {
        source: Qt.resolvedUrl("/var/lib/AccountsService/icons/" + user)
        height: parent.width ; width: parent.width
      }
      Image {
        source: Qt.resolvedUrl(config.LoginBackground == "true" ? "../assets/maskDark.svg" : "../assets/mask.svg")
        height: parent.width ; width: parent.width
      }
      Image {
        source: Qt.resolvedUrl("../assets/ring.svg")
        height: parent.width ; width: parent.width
      }
      anchors.horizontalCenter: parent.horizontalCenter
    }

    UserField {
      id: userField
      height: inputHeight
      width: parent.width
      onActiveFocusChanged: {
        if (activeFocus) {
          vkb.activeField = 0
          vkb.forceActiveFocus()
        }
      }
    }

    PasswordField {
      id: passwordField
      height: inputHeight
      width: parent.width
      onAccepted: loginButton.clicked()
      onActiveFocusChanged: {
        if (activeFocus) {
          vkb.activeField = 1
          vkb.forceActiveFocus()
        }
      }
    }

    Button {
      id: loginButton
      height: inputHeight
      width: parent.width
      enabled: user != "" && password != "" ? true : false
      hoverEnabled: true
      contentItem: Text {
        id: buttonText
        renderType: Text.NativeRendering
        font { family: config.Font; pointSize: config.FontSize; bold: true }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: "#11111B"
        text: "Login"
      }
      background: Rectangle {
        id: buttonBackground
        color: "#B4BEFE"
        radius: 3
      }
      states: [
        State { name: "pressed"; when: loginButton.down; PropertyChanges { target: buttonBackground; color: "#A6ADC8" } },
        State { name: "hovered"; when: loginButton.hovered; PropertyChanges { target: buttonBackground; color: "#A6ADC8" } },
        State { name: "enabled"; when: loginButton.enabled; PropertyChanges { target: buttonBackground } }
      ]
      transitions: Transition { PropertyAnimation { properties: "color"; duration: 300 } }
      onClicked: { sddm.login(user, password, session) }
    }
  }

  Item {
    id: keyboardContainer
    anchors {
      bottom: parent.bottom
      left: parent.left
      right: parent.right
    }
    height: Screen.height * 0.28
    z: 5

    VirtualKeyboard {
      id: vkb
      anchors.fill: parent
      userField: userField
      passwordField: passwordField
    }
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      passwordField.text = ""
      vkb.forceActiveFocus()
    }
  }

  Component.onCompleted: vkb.forceActiveFocus()
}
