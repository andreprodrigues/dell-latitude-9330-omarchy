import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Detail popup: runs the sibling `dell-health` script, which prints JSON
// {status, problems, checkedAt, items: [{section, label, value, status, hint}]},
// and lists the checks grouped by section.
Panel {
  id: root
  moduleName: "dell9330.health"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string scriptPath: String(Qt.resolvedUrl("dell-health")).replace(/^file:\/\//, "")
  readonly property int refreshIntervalSec: Math.max(15, Number(setting("refreshIntervalSec", 60)) || 60)

  property string status: "ok"
  property string problems: ""
  property var sections: []
  property string checkedAt: ""
  property bool failed: false

  readonly property color okColor: "#8ec07c"
  readonly property color warnColor: "#e5c07b"

  function statusColor(s) {
    if (s === "ok") return okColor
    if (s === "warn") return warnColor
    if (s === "bad") return Commons.Color.urgent
    return Commons.Color.muted
  }

  function open() {
    root.controller.show()
    root.refresh()
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (!checkProc.running) checkProc.running = true
  }

  function notifySummary() {
    var body = root.status === "ok" ? "All checks pass" : root.problems
    Quickshell.execDetached(["omarchy-notification-send", "-g", "󰈷", "Dell health", body])
  }

  function applyReport(raw) {
    var report
    try {
      report = JSON.parse(raw)
    } catch (e) {
      root.failed = true
      return
    }
    root.failed = false
    root.status = report.status || "ok"
    root.problems = report.problems || ""
    root.checkedAt = Qt.formatTime(new Date((report.checkedAt || 0) * 1000), "HH:mm")

    var order = []
    var grouped = {}
    var items = report.items || []
    for (var i = 0; i < items.length; i++) {
      var s = items[i].section
      if (!grouped[s]) { grouped[s] = []; order.push(s) }
      grouped[s].push(items[i])
    }
    root.sections = order.map(function(name) { return { title: name, items: grouped[name] } })
  }

  Process {
    id: checkProc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyReport(String(text || "").trim())
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.refresh()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(12)

          // Header: title, overall state, actions.
          Item {
            width: parent.width
            height: Math.max(titleColumn.implicitHeight, actions.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Latitude 9330"
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.failed ? "Health check failed to run"
                  : (root.status === "ok" ? "All good" : (root.status === "bad" ? "Needs attention" : "Worth a look"))
                    + (root.checkedAt ? "  ·  checked " + root.checkedAt : "")
                color: root.failed ? Commons.Color.urgent : root.statusColor(root.status)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Re-run checks"
                onClicked: root.refresh()
              }

              PanelActionButton {
                iconText: "󰦪"
                tooltipText: "Full report in a terminal"
                onClicked: Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", root.scriptPath + " --text"])
              }

              PanelActionButton {
                iconText: "󰌱"
                tooltipText: "fprintd log"
                onClicked: Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "journalctl -u fprintd -b -f -n 50"])
              }
            }
          }

          Repeater {
            model: root.sections

            delegate: Column {
              required property var modelData
              width: content.width
              spacing: Style.space(6)

              PanelSeparator { width: parent.width }

              PanelSectionHeader {
                text: modelData.title.toUpperCase()
              }

              Repeater {
                model: modelData.items

                delegate: Item {
                  id: row
                  required property var modelData
                  readonly property bool showHint: modelData.hint !== "" && modelData.status !== "ok"
                  width: parent.width
                  height: rowColumn.implicitHeight

                  Rectangle {
                    id: dot
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    anchors.left: parent.left
                    y: Math.round((labelText.implicitHeight - height) / 2)
                    color: root.statusColor(row.modelData.status)
                  }

                  Column {
                    id: rowColumn
                    anchors.left: dot.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    spacing: Style.space(2)

                    Row {
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        id: labelText
                        width: Style.space(110)
                        textFormat: Text.PlainText
                        text: row.modelData.label
                        color: Commons.Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width - labelText.width - parent.spacing
                        textFormat: Text.PlainText
                        text: row.modelData.value
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      }
                    }

                    Text {
                      visible: row.showHint
                      width: parent.width
                      leftPadding: labelText.width + Style.space(8)
                      textFormat: Text.PlainText
                      text: "→ " + row.modelData.hint
                      color: root.statusColor(row.modelData.status)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
