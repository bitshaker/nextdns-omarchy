import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property int refreshIntervalSec: 15

  property bool installed: false
  property bool configured: false
  property bool running: false
  property bool active: false
  property bool busy: false
  property string profileId: ""
  property string errorMessage: ""
  property string actionStatus: ""

  property bool _statusDone: false
  property bool _configDone: false
  property int _statusExitCode: -1
  property int _configExitCode: -1
  property string _actionKind: ""
  property string _successMessage: ""

  signal refreshed()

  function normalizedProfileId(value) {
    var id = String(value || "").trim()
    return /^[A-Za-z0-9]{3,64}$/.test(id) ? id : ""
  }

  function refresh() {
    if (whichProcess.running || statusProcess.running || configProcess.running) return
    whichProcess.running = true
  }

  function refreshInstalledState() {
    _statusDone = false
    _configDone = false
    _statusExitCode = -1
    _configExitCode = -1
    statusProcess.running = true
    configProcess.running = true
  }

  function finishRefreshIfReady() {
    if (!_statusDone || !_configDone) return

    var statusText = String(statusStdout.text || "").trim()
    var configText = String(configStdout.text || "")
    var profileMatch = configText.match(/^profile\s+([^\s]+)\s*$/m)
    var activeMatch = configText.match(/^auto-activate\s+(true|false)\s*$/m)

    running = _statusExitCode === 0 && statusText === "running"
    configured = _configExitCode === 0
    profileId = profileMatch && profileMatch[1] ? String(profileMatch[1]) : ""
    active = configured && running && activeMatch && activeMatch[1] === "true"

    if (configured) {
      errorMessage = ""
    } else if (_configExitCode !== 0) {
      var detail = String(configStderr.text || statusStderr.text || "").trim()
      if (detail !== "" && !/system not supported/i.test(detail)) errorMessage = detail
    }

    refreshed()
  }

  function runAction(command, kind, label, successMessage) {
    if (busy) return
    busy = true
    errorMessage = ""
    actionStatus = label
    _actionKind = kind
    _successMessage = successMessage
    actionProcess.command = command
    actionProcess.running = true
  }

  function toggleActive() {
    if (!installed || !configured || busy) return
    if (active) {
      runAction(["pkexec", "nextdns", "deactivate"], "toggle", "Turning NextDNS off…", "NextDNS is off")
    } else {
      runAction(["pkexec", "nextdns", "activate"], "toggle", "Turning NextDNS on…", "NextDNS is on")
    }
  }

  function selectProfile(value) {
    var id = normalizedProfileId(value)
    if (id === "") {
      errorMessage = "Enter a valid NextDNS profile ID"
      return
    }
    if (!installed || busy) return
    if (!configured) {
      setup(id)
      return
    }
    if (id === profileId) return
    runAction(
      ["pkexec", "nextdns", "config", "set", "-profile=" + id],
      "profile",
      "Changing NextDNS profile…",
      "Profile changed"
    )
  }

  function setup(value) {
    var id = normalizedProfileId(value)
    if (id === "") {
      errorMessage = "Enter a valid NextDNS profile ID"
      return
    }
    if (!installed || busy) return
    runAction(
      ["pkexec", "nextdns", "install", "-profile=" + id, "-report-client-info", "-auto-activate"],
      "setup",
      "Configuring NextDNS…",
      "NextDNS configured"
    )
  }

  function installCli() {
    if (installed) return
    Quickshell.execDetached(["omarchy-launch-terminal", "omarchy", "pkg", "aur", "add", "nextdns"])
    actionStatus = "Installer opened in a terminal"
    statusClearTimer.restart()
  }

  function finishAction(exitCode, output, errorOutput) {
    busy = false
    if (exitCode === 0) {
      errorMessage = ""
      actionStatus = _successMessage
    } else {
      var detail = String(errorOutput || output || "NextDNS command failed").trim()
      errorMessage = detail === "" ? "NextDNS command failed" : detail
      actionStatus = ""
    }
    _actionKind = ""
    _successMessage = ""
    delayedRefresh.restart()
    statusClearTimer.restart()
  }

  Timer {
    id: refreshTimer
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: statusClearTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: ["sh", "-lc", "command -v nextdns >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) {
        root.refreshInstalledState()
      } else {
        root.configured = false
        root.running = false
        root.active = false
        root.profileId = ""
        root.errorMessage = ""
        root.refreshed()
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: ["nextdns", "status"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._statusExitCode = exitCode
      root._statusDone = true
      root.finishRefreshIfReady()
    }
  }

  Process {
    id: configProcess
    running: false
    command: ["nextdns", "config", "list"]
    stdout: StdioCollector { id: configStdout; waitForEnd: true }
    stderr: StdioCollector { id: configStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._configExitCode = exitCode
      root._configDone = true
      root.finishRefreshIfReady()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var output = String(actionStdout.text || "")
      var errorOutput = String(actionStderr.text || "")
      if (exitCode === 0 && root._actionKind === "profile") {
        root.actionStatus = "Restarting NextDNS…"
        restartProcess.running = true
      } else {
        root.finishAction(exitCode, output, errorOutput)
      }
    }
  }

  Process {
    id: restartProcess
    running: false
    command: ["pkexec", "nextdns", "restart"]
    stdout: StdioCollector { id: restartStdout; waitForEnd: true }
    stderr: StdioCollector { id: restartStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishAction(exitCode, String(restartStdout.text || ""), String(restartStderr.text || ""))
    }
  }
}
