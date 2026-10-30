import QtQuick
import qs.Commons
import qs.Ui

// Bar icon for the Dell health panel: a fingerprint glyph while every check
// passes, an alert glyph in the urgent color when one warns or fails. Left
// opens the panel, middle re-runs the checks, right sends a summary toast.
BarWidget {
  id: root
  moduleName: "dell9330.health"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Shape contract the bar uses to route summon/hide and popout switching.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property string status: panelLoader.item ? panelLoader.item.status : "ok"
  readonly property string problems: panelLoader.item ? panelLoader.item.problems : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    slotSize: Style.bar.statusSlot
    text: root.status === "ok" ? "󰈷" : "󰀪"
    active: root.status !== "ok"
    tooltipText: root.opened ? "" : (root.status === "ok" ? "Dell health: all good" : "Dell health: " + root.problems)

    onPressed: function(b) {
      if (!root.bar || !panelLoader.item) return
      if (b === Qt.MiddleButton) panelLoader.item.refresh()
      else if (b === Qt.RightButton) panelLoader.item.notifySummary()
      else panelLoader.item.toggle()
    }
  }
}
