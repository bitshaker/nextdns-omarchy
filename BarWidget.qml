import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Profiles.js" as Profiles

BarWidget {
  id: root
  moduleName: "bitshaker.nextdns-omarchy"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function profileName(id) {
    var name = Profiles.savedNameFor(Profiles.fromSettings(root.settings), id)
    return name === "" ? "Unsaved profile" : name
  }

  function statusTooltip() {
    if (!nextdns.installed) return "NextDNS CLI is not installed"
    if (!nextdns.configured) return "NextDNS needs configuration"
    if (nextdns.busy) return nextdns.actionStatus || "Working…"
    if (nextdns.errorMessage !== "") return nextdns.errorMessage
    if (!nextdns.active) return "NextDNS off · system DNS"
    var name = profileName(nextdns.profileId)
    return name === "" ? "NextDNS on" : "NextDNS on · " + name
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
    panelLoader.item.nextdns = nextdns
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  NextDnsService {
    id: nextdns
    refreshIntervalSec: Number(root.setting("refreshIntervalSec", 15))
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf132"
    dimmed: !nextdns.active
    active: nextdns.errorMessage !== ""
    tooltipText: root.statusTooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) nextdns.toggleActive()
      else if (buttonCode === Qt.MiddleButton) nextdns.refresh()
      else root.toggle()
    }
  }
}
