import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Profiles.js" as Profiles

Panel {
  id: root
  moduleName: "bitshaker.nextdns-omarchy"
  ipcTarget: "bitshaker.nextdns-omarchy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var nextdns: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var savedProfiles: Profiles.fromSettings(root.settings)
  readonly property string activeProfileName: {
    if (!nextdns || !nextdns.configured || nextdns.profileId === "") return ""
    var name = Profiles.savedNameFor(savedProfiles, nextdns.profileId)
    return name === "" ? "Unsaved profile" : name
  }

  property bool profileEditorOpen: false
  property string editingProfileId: ""
  property string profileEditorError: ""
  property string profileEditorMessage: ""

  function open() {
    if (nextdns) nextdns.refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function stateMeta() {
    if (!nextdns || !nextdns.installed) return "CLI NOT INSTALLED"
    if (!nextdns.configured) return "SETUP REQUIRED"
    if (nextdns.busy) return String(nextdns.actionStatus || "WORKING").toUpperCase()
    if (nextdns.active) return "PROTECTED · DOH"
    return "OFF · SYSTEM DNS"
  }

  function applyProfile(id) {
    if (!nextdns) return
    nextdns.selectProfile(id)
  }

  function persistProfiles(values) {
    var profiles = Profiles.normalize(values)
    var entry = { id: root.moduleName }
    if (root.settings && root.settings.refreshIntervalSec !== undefined)
      entry.refreshIntervalSec = root.settings.refreshIntervalSec
    entry.profiles = profiles

    // Update the live panel and bar immediately. The shell write then feeds
    // the same entry back through the normal settings binding.
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function beginProfileEdit(profile) {
    if (!profile) return
    profileEditorOpen = true
    editingProfileId = String(profile.id)
    profileNameField.text = String(profile.name)
    profileIdField.text = String(profile.id)
    profileEditorError = ""
    profileEditorMessage = ""
    Qt.callLater(function() {
      profileNameField.selectAll()
      profileNameField.forceActiveFocus()
    })
  }

  function beginNewProfile() {
    editingProfileId = ""
    profileNameField.text = ""
    profileIdField.text = ""
    profileEditorError = ""
    profileEditorMessage = ""
    profileEditorOpen = true
    Qt.callLater(function() { profileNameField.forceActiveFocus() })
  }

  function clearProfileEditor() {
    profileEditorOpen = false
    editingProfileId = ""
    profileNameField.text = ""
    profileIdField.text = ""
    profileEditorError = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function saveProfile() {
    var name = String(profileNameField.text || "").trim()
    var id = Profiles.profileId(profileIdField.text)
    if (name === "") {
      profileEditorError = "Enter a profile name"
      return
    }
    if (name.length > 80) {
      profileEditorError = "Profile names must be 80 characters or fewer"
      return
    }
    if (id === "") {
      profileEditorError = "Enter a valid NextDNS profile ID"
      return
    }

    var values = savedProfiles.slice(0)
    var editIndex = -1
    var duplicateIndex = -1
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === editingProfileId) editIndex = i
      if (values[i].id === id) duplicateIndex = i
    }

    if (editingProfileId === "" && duplicateIndex !== -1) {
      profileEditorError = "That profile ID is already saved"
      return
    }
    if (editingProfileId !== "" && duplicateIndex !== -1 && duplicateIndex !== editIndex) {
      profileEditorError = "That profile ID belongs to another saved profile"
      return
    }

    var value = { name: name, id: id }
    if (editIndex === -1) values.push(value)
    else values[editIndex] = value

    persistProfiles(values)
    profileEditorMessage = editingProfileId === "" ? "Profile added" : "Profile updated"
    profileMessageTimer.restart()
    clearProfileEditor()
  }

  function removeProfile(profile) {
    if (!profile) return
    var values = []
    for (var i = 0; i < savedProfiles.length; i++) {
      if (savedProfiles[i].id !== String(profile.id)) values.push(savedProfiles[i])
    }
    persistProfiles(values)
    if (editingProfileId === String(profile.id)) clearProfileEditor()
    profileEditorMessage = "Removed " + String(profile.name)
    profileEditorError = ""
    profileMessageTimer.restart()
  }

  Timer {
    id: profileMessageTimer
    interval: 2600
    repeat: false
    onTriggered: root.profileEditorMessage = ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(590))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: profileNameField.activeFocus || profileIdField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "r" || text === "R") && root.nextdns) root.nextdns.refresh()
        if ((text === "t" || text === "T") && root.nextdns) root.nextdns.toggleActive()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(10)

        PanelHero {
          id: hero
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: "NextDNS"
          meta: root.stateMeta()
          detail: ""
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "\uf132"
              color: root.nextdns && root.nextdns.active ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }
          trailingControl: Component {
            Row {
              width: implicitWidth
              height: implicitHeight
              spacing: Style.space(8)

              BorderSurface {
                visible: root.activeProfileName !== ""
                width: Math.min(Style.space(118), activeProfileText.implicitWidth + Style.space(12))
                height: powerSwitch.implicitHeight
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                radius: Style.cornerRadius

                Text {
                  id: activeProfileText
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  textFormat: Text.PlainText
                  text: root.activeProfileName
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }

              ToggleSwitch {
                id: powerSwitch
                width: implicitWidth
                height: implicitHeight
                checked: root.nextdns ? root.nextdns.active : false
                busy: root.nextdns ? root.nextdns.busy : false
                interactive: root.nextdns && root.nextdns.installed && root.nextdns.configured
                opacity: interactive ? 1 : 0.45
                foreground: root.foreground
                accent: Color.accent
                onToggled: if (root.nextdns) root.nextdns.toggleActive()
              }
            }
          }
        }

        Text {
          visible: root.nextdns && root.nextdns.errorMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.nextdns ? root.nextdns.errorMessage : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.nextdns && root.nextdns.actionStatus !== "" && root.nextdns.errorMessage === ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.nextdns ? root.nextdns.actionStatus : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: root.nextdns && !root.nextdns.installed
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "The NextDNS CLI is required. Installation opens an AUR command in a terminal and does not run until you choose this action."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            text: "Install NextDNS CLI"
            iconText: "↓"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.nextdns) root.nextdns.installCli()
          }
        }

        Column {
          visible: root.nextdns && root.nextdns.installed
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "PROFILES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.savedProfiles

            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(6)

              Button {
                id: profileButton
                width: Math.max(Style.space(120), parent.width - editProfileButton.width - removeProfileButton.width - parent.spacing * 2)
                text: String(parent.modelData.name)
                tooltipText: "Switch to " + String(parent.modelData.id)
                iconText: root.nextdns && root.nextdns.profileId === String(parent.modelData.id) ? "✓" : ""
                leftAlign: true
                selected: root.nextdns && root.nextdns.profileId === String(parent.modelData.id)
                enabled: root.nextdns && !root.nextdns.busy
                verticalPadding: Style.space(3)
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.applyProfile(String(parent.modelData.id))
              }

              Button {
                id: editProfileButton
                width: Style.space(30)
                height: profileButton.implicitHeight
                iconText: "󰏫"
                iconSize: Style.font.bodySmall
                tooltipText: "Edit " + String(parent.modelData.name)
                horizontalPadding: 0
                verticalPadding: 0
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.beginProfileEdit(parent.modelData)
              }

              Button {
                id: removeProfileButton
                width: Style.space(30)
                height: profileButton.implicitHeight
                iconText: "×"
                iconSize: Style.font.bodySmall
                tooltipText: "Remove " + String(parent.modelData.name) + " from this list"
                horizontalPadding: 0
                verticalPadding: 0
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: root.removeProfile(parent.modelData)
              }
            }
          }

          Text {
            visible: root.savedProfiles.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: root.nextdns && root.nextdns.configured
              ? "No saved profiles."
              : "Add a profile to finish setup."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              id: addProfileToggle
              width: (parent.width - parent.spacing) / 2
              text: root.profileEditorOpen ? "Hide" : "Add profile"
              iconText: root.profileEditorOpen ? "−" : "+"
              verticalPadding: Style.space(3)
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.profileEditorOpen) root.clearProfileEditor()
                else root.beginNewProfile()
              }
            }

            Button {
              id: refreshButton
              width: (parent.width - parent.spacing) / 2
              text: "Refresh"
              iconText: "󰑐"
              verticalPadding: Style.space(3)
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.nextdns) root.nextdns.refresh()
            }
          }

          Column {
            visible: root.profileEditorOpen
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: root.editingProfileId === "" ? "ADD PROFILE" : "EDIT PROFILE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: profileNameField
                width: Math.max(Style.space(120), (parent.width - parent.spacing) * 0.58)
                placeholderText: "Profile name"
                foreground: root.foreground
                onAccepted: profileIdField.forceActiveFocus()
              }

              TextField {
                id: profileIdField
                width: Math.max(Style.space(90), parent.width - profileNameField.width - parent.spacing)
                placeholderText: "Profile ID"
                foreground: root.foreground
                onAccepted: root.saveProfile()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: root.editingProfileId === "" ? "Save profile" : "Save changes"
                enabled: profileNameField.text.trim() !== "" && profileIdField.text.trim() !== ""
                verticalPadding: Style.space(3)
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.saveProfile()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Cancel"
                verticalPadding: Style.space(3)
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.clearProfileEditor()
              }
            }
          }

          Text {
            visible: root.profileEditorError !== "" || root.profileEditorMessage !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.profileEditorError !== "" ? root.profileEditorError : root.profileEditorMessage
            color: root.profileEditorError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
      }
    }
  }
}
