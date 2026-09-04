import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string nextdnsPath: "/usr/bin/nextdns"
  readonly property int maxOutputBytes: 4096
  readonly property int maxErrorBytes: 512
  readonly property var safeEnvironment: ({ "PATH": "/usr/bin", "LC_ALL": "C" })

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
  property bool _refreshTimedOut: false
  property string _verifyOutput: ""
  property bool _verifyOverflow: false
  property bool _verifyTimedOut: false
  property string _packageVerifyOutput: ""
  property bool _packageVerifyOverflow: false
  property string _statusOutput: ""
  property string _statusError: ""
  property bool _statusOverflow: false
  property string _configOutput: ""
  property string _configError: ""
  property bool _configOverflow: false
  property string _actionOutput: ""
  property string _actionError: ""
  property bool _actionOverflow: false
  property string _actionKind: ""
  property string _successMessage: ""

  signal refreshed()

  function normalizedProfileId(value) {
    var id = String(value === undefined || value === null ? "" : value).trim()
    return /^[0-9a-f]{6}$/.test(id) ? id : ""
  }

  function utf8Bytes(value) {
    var text = String(value || "")
    var bytes = 0
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i)
      if (code < 0x80) bytes += 1
      else if (code < 0x800) bytes += 2
      else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
               && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
        bytes += 4
        i++
      } else bytes += 3
    }
    return bytes
  }

  function truncateUtf8(value, limit) {
    var text = String(value || "")
    var bytes = 0
    var end = 0
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i)
      var width = code < 0x80 ? 1 : (code < 0x800 ? 2 : 3)
      var chars = 1
      if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
          && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
        width = 4
        chars = 2
      }
      if (bytes + width > limit) break
      bytes += width
      end = i + chars
      if (chars === 2) i++
    }
    return text.slice(0, end)
  }

  function capture(current, chunk) {
    var combined = String(current || "") + String(chunk || "")
    if (utf8Bytes(combined) <= maxOutputBytes) return { text: combined, overflow: false }
    return { text: truncateUtf8(combined, maxOutputBytes), overflow: true }
  }

  function plainError(value, fallback) {
    var text = String(value || "")
      .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, "")
      .trim()
    if (text === "") text = String(fallback || "NextDNS command failed")
    return truncateUtf8(text, maxErrorBytes)
  }

  function nextdnsCommand(args, seconds) {
    return [
      "/usr/bin/timeout", "--kill-after=3s", String(seconds) + "s", nextdnsPath
    ].concat(args)
  }

  function privilegedNextdnsCommand(args, seconds) {
    return [
      "/usr/bin/pkexec", "/usr/bin/timeout", "--kill-after=3s",
      String(seconds) + "s", nextdnsPath
    ].concat(args)
  }

  function profileTransactionCommand(newProfileId, previousProfileId) {
    var script = ""
      + "set -u; "
      + "new_profile=$1; previous_profile=$2; rollback_needed=1; "
      + "run_nextdns() { /usr/bin/timeout --kill-after=3s 15s /usr/bin/nextdns \"$@\"; }; "
      + "rollback() { status=$?; trap - EXIT TERM INT HUP; "
      + "  if [ \"$rollback_needed\" -eq 1 ]; then "
      + "    if run_nextdns config set \"-profile=${previous_profile}\" && run_nextdns restart; then "
      + "      printf '%s\\n' 'NextDNS operation failed; the previous profile was restored' >&2; "
      + "      [ \"$status\" -eq 0 ] && status=71; "
      + "    else "
      + "      printf '%s\\n' 'NextDNS operation failed and automatic rollback failed; verify the active profile manually' >&2; "
      + "      status=72; "
      + "    fi; "
      + "  fi; exit \"$status\"; }; "
      + "trap rollback EXIT; trap 'exit 124' TERM INT HUP; "
      + "run_nextdns config set \"-profile=${new_profile}\" || exit 70; "
      + "run_nextdns restart || exit 71; "
      + "rollback_needed=0"
    return [
      "/usr/bin/pkexec", "/usr/bin/env", "-i", "PATH=/usr/bin", "LC_ALL=C",
      "/usr/bin/timeout", "--kill-after=40s", "75s",
      "/usr/bin/bash", "--noprofile", "--norc", "-c", script,
      "nextdns-profile-transaction", newProfileId, previousProfileId
    ]
  }

  function refresh() {
    if (verifyProcess.running || packageVerifyProcess.running
        || statusProcess.running || configProcess.running || busy) return
    _verifyOutput = ""
    _verifyOverflow = false
    _verifyTimedOut = false
    _packageVerifyOutput = ""
    _packageVerifyOverflow = false
    verifyProcess.running = true
    verifyWatchdog.restart()
  }

  function protectedPath(metadata) {
    var lines = String(metadata || "").trim().split("\n")
    if (lines.length !== 4) return false
    var expectedPaths = ["/", "/usr", "/usr/bin", nextdnsPath]
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("|")
      if (parts.length !== 4 || parts[0] !== expectedPaths[i]) return false
      if (parts[1] !== "0" || !/^[0-7]{3,4}$/.test(parts[2])) return false
      var mode = parseInt(parts[2], 8)
      if ((mode & 0x12) !== 0) return false
      if (i < 3 && parts[3] !== "directory") return false
      if (i === 3 && (parts[3] !== "regular file" || (mode & 0x49) === 0)) return false
    }
    return true
  }

  function finishPathVerification(exitCode) {
    if (_verifyTimedOut) return
    var exists = exitCode === 0
    if (!exists || _verifyOverflow || !protectedPath(_verifyOutput)) {
      verifyWatchdog.stop()
      installed = false
      configured = false
      running = false
      active = false
      profileId = ""
      errorMessage = exists ? "Refusing an unprotected NextDNS CLI path at /usr/bin/nextdns" : ""
      refreshed()
      return
    }
    Qt.callLater(function() {
      packageVerifyProcess.running = true
      verifyWatchdog.restart()
    })
  }

  function finishPackageVerification(exitCode) {
    verifyWatchdog.stop()
    if (_verifyTimedOut) return
    var trusted = exitCode === 0 && !_packageVerifyOverflow
      && String(_packageVerifyOutput || "").trim() === "nextdns"
    installed = trusted
    if (!trusted) {
      configured = false
      running = false
      active = false
      profileId = ""
      errorMessage = "Refusing a /usr/bin/nextdns executable not owned by the nextdns package"
      refreshed()
      return
    }
    errorMessage = ""
    Qt.callLater(refreshInstalledState)
  }

  function refreshInstalledState() {
    _statusDone = false
    _configDone = false
    _statusExitCode = -1
    _configExitCode = -1
    _refreshTimedOut = false
    _statusOutput = ""
    _statusError = ""
    _statusOverflow = false
    _configOutput = ""
    _configError = ""
    _configOverflow = false
    statusProcess.running = true
    configProcess.running = true
    refreshWatchdog.restart()
  }

  function finishRefreshIfReady() {
    if (!_statusDone || !_configDone) return
    refreshWatchdog.stop()

    var profileMatch = _configOutput.match(/^profile\s+([0-9a-f]{6})\s*$/m)
    var activeMatch = _configOutput.match(/^auto-activate\s+(true|false)\s*$/m)
    running = !_refreshTimedOut && !_statusOverflow && _statusExitCode === 0
      && String(_statusOutput).trim() === "running"
    configured = !_refreshTimedOut && !_configOverflow && _configExitCode === 0
    profileId = profileMatch && profileMatch[1] ? String(profileMatch[1]) : ""
    active = configured && running && activeMatch && activeMatch[1] === "true"

    if (_refreshTimedOut) errorMessage = "NextDNS status check timed out"
    else if (_statusOverflow || _configOverflow) errorMessage = "NextDNS returned more status data than allowed"
    else if (configured) errorMessage = ""
    else if (_configExitCode !== 0) {
      var detail = plainError(_configError || _statusError, "NextDNS is not configured")
      if (!/system not supported/i.test(detail)) errorMessage = detail
    }
    refreshed()
  }

  function resetActionOutput() {
    _actionOutput = ""
    _actionError = ""
    _actionOverflow = false
  }

  function runAction(command, kind, label, successMessage) {
    if (busy) return
    busy = true
    errorMessage = ""
    actionStatus = label
    _actionKind = kind
    _successMessage = successMessage
    resetActionOutput()
    actionProcess.command = command
    actionProcess.running = true
    actionWatchdog.restart()
  }

  function toggleActive() {
    if (!installed || !configured || busy) return
    if (active) runAction(privilegedNextdnsCommand(["deactivate"], 30), "toggle", "Turning NextDNS off…", "NextDNS is off")
    else runAction(privilegedNextdnsCommand(["activate"], 30), "toggle", "Turning NextDNS on…", "NextDNS is on")
  }

  function selectProfile(value) {
    var id = normalizedProfileId(value)
    if (id === "") {
      errorMessage = "Enter a valid six-character lowercase hexadecimal NextDNS profile ID"
      return
    }
    if (!installed || busy) return
    if (!configured) {
      setup(id)
      return
    }
    if (id === profileId) return
    var previousId = normalizedProfileId(profileId)
    if (previousId === "") {
      errorMessage = "Cannot change profiles without a valid current profile for rollback"
      return
    }
    runAction(
      profileTransactionCommand(id, previousId),
      "profile", "Changing and restarting NextDNS…", "Profile changed"
    )
  }

  function setup(value) {
    var id = normalizedProfileId(value)
    if (id === "") {
      errorMessage = "Enter a valid six-character lowercase hexadecimal NextDNS profile ID"
      return
    }
    if (!installed || busy) return
    runAction(
      privilegedNextdnsCommand(["install", "-profile=" + id, "-report-client-info", "-auto-activate"], 60),
      "setup", "Configuring NextDNS…", "NextDNS configured"
    )
  }

  function installCli() {
    if (installed) return
    Quickshell.execDetached([
      "/usr/share/omarchy/bin/omarchy-launch-terminal",
      "/usr/share/omarchy/bin/omarchy", "pkg", "aur", "add", "nextdns"
    ])
    actionStatus = "Installer opened in a terminal"
    statusClearTimer.restart()
  }

  function actionFailure(fallback) {
    if (_actionOverflow) return "NextDNS returned more output than allowed"
    return plainError(_actionError || _actionOutput, fallback)
  }

  function finishSuccess() {
    actionWatchdog.stop()
    busy = false
    errorMessage = ""
    actionStatus = _successMessage
    clearActionState()
    delayedRefresh.restart()
    statusClearTimer.restart()
  }

  function finishFailure(message) {
    actionWatchdog.stop()
    busy = false
    errorMessage = plainError(message, "NextDNS command failed")
    actionStatus = ""
    clearActionState()
    delayedRefresh.restart()
  }

  function clearActionState() {
    _actionKind = ""
    _successMessage = ""
  }

  function stopAllProcesses() {
    if (verifyProcess.running) verifyProcess.running = false
    if (packageVerifyProcess.running) packageVerifyProcess.running = false
    if (statusProcess.running) statusProcess.running = false
    if (configProcess.running) configProcess.running = false
    if (actionProcess.running) actionProcess.running = false
  }

  Timer {
    id: refreshTimer
    interval: Math.max(5, Math.min(300, root.refreshIntervalSec)) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: verifyWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      root._verifyTimedOut = true
      if (verifyProcess.running) verifyProcess.running = false
      if (packageVerifyProcess.running) packageVerifyProcess.running = false
      root.installed = false
      root.errorMessage = "NextDNS CLI verification timed out"
      root.refreshed()
    }
  }

  Timer {
    id: refreshWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      root._refreshTimedOut = true
      if (statusProcess.running) statusProcess.running = false
      if (configProcess.running) configProcess.running = false
    }
  }

  Timer {
    id: actionWatchdog
    interval: 125000
    repeat: false
    onTriggered: {
      if (actionProcess.running) actionProcess.running = false
      root.finishFailure("NextDNS operation timed out; verify the active profile manually")
    }
  }

  Timer { id: delayedRefresh; interval: 800; repeat: false; onTriggered: root.refresh() }
  Timer { id: statusClearTimer; interval: 2600; repeat: false; onTriggered: root.actionStatus = "" }

  Process {
    id: verifyProcess
    running: false
    clearEnvironment: true
    environment: root.safeEnvironment
    command: [
      "/usr/bin/timeout", "--kill-after=1s", "3s",
      "/usr/bin/stat", "--format=%n|%u|%a|%F",
      "/", "/usr", "/usr/bin", root.nextdnsPath
    ]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._verifyOutput, data)
        root._verifyOutput = result.text
        if (result.overflow) root._verifyOverflow = true
      }
    }
    onExited: function(exitCode) { root.finishPathVerification(exitCode) }
  }

  Process {
    id: packageVerifyProcess
    running: false
    clearEnvironment: true
    environment: root.safeEnvironment
    command: [
      "/usr/bin/timeout", "--kill-after=1s", "3s",
      "/usr/bin/pacman", "-Qqo", root.nextdnsPath
    ]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._packageVerifyOutput, data)
        root._packageVerifyOutput = result.text
        if (result.overflow) root._packageVerifyOverflow = true
      }
    }
    onExited: function(exitCode) { root.finishPackageVerification(exitCode) }
  }

  Process {
    id: statusProcess
    running: false
    environment: root.safeEnvironment
    command: root.nextdnsCommand(["status"], 5)
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._statusOutput, data)
        root._statusOutput = result.text
        if (result.overflow) root._statusOverflow = true
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._statusError, data)
        root._statusError = result.text
        if (result.overflow) root._statusOverflow = true
      }
    }
    onExited: function(exitCode) {
      root._statusExitCode = exitCode
      root._statusDone = true
      root.finishRefreshIfReady()
    }
  }

  Process {
    id: configProcess
    running: false
    environment: root.safeEnvironment
    command: root.nextdnsCommand(["config", "list"], 5)
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._configOutput, data)
        root._configOutput = result.text
        if (result.overflow) root._configOverflow = true
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._configError, data)
        root._configError = result.text
        if (result.overflow) root._configOverflow = true
      }
    }
    onExited: function(exitCode) {
      root._configExitCode = exitCode
      root._configDone = true
      root.finishRefreshIfReady()
    }
  }

  Process {
    id: actionProcess
    running: false
    environment: root.safeEnvironment
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._actionOutput, data)
        root._actionOutput = result.text
        if (result.overflow) root._actionOverflow = true
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        var result = root.capture(root._actionError, data)
        root._actionError = result.text
        if (result.overflow) root._actionOverflow = true
      }
    }
    onExited: function(exitCode) {
      actionWatchdog.stop()
      if (exitCode === 0 && !root._actionOverflow) root.finishSuccess()
      else root.finishFailure(root.actionFailure("NextDNS command failed"))
    }
  }

  Component.onDestruction: {
    refreshTimer.stop()
    verifyWatchdog.stop()
    refreshWatchdog.stop()
    actionWatchdog.stop()
    delayedRefresh.stop()
    statusClearTimer.stop()
    stopAllProcesses()
  }
}
