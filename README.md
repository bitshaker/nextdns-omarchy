# NextDNS Control for Omarchy

A native Omarchy bar widget for the NextDNS CLI. It shows whether NextDNS is active, opens a detail panel, switches profiles, and turns NextDNS on or off.

## What it does

- Reads state with `nextdns status` and `nextdns config list`.
- Activates or deactivates NextDNS through a graphical authorization prompt.
- Changes the configured profile and restarts the service.
- Adds, edits, and removes any number of named profiles directly in the panel.
- Detects a missing CLI and offers to open the Omarchy AUR installation command in a terminal.
- Stores profile names and IDs in the local Omarchy bar configuration. The repository contains no profile IDs or NextDNS credentials.

Installing the Omarchy plugin itself does not install packages or run setup commands.

## Requirements

- Omarchy 4 with the Quattro shell plugin system.
- The NextDNS CLI from the AUR (`nextdns`).
- A working graphical polkit agent. Omarchy provides one through its shell.

The panel can open the AUR installation flow, or install manually:

```sh
omarchy pkg aur add nextdns
```

If the CLI is installed but not configured, entering a profile ID and choosing **Configure** runs the workstation setup with client reporting and automatic activation.

## Development install

The plugin ID is `bitshaker.nextdns-omarchy`. Validate it from the repository root:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml NextDnsService.qml
```

## Controls

- Left click: open or close the panel.
- Right click: turn NextDNS on or off.
- Middle click: refresh status.
- Panel switch: turn NextDNS on or off.
- Profile button: change profile, then restart NextDNS.

Turning NextDNS off means **system DNS**. The resolver selected by the operating system may be the network DNS or a configured fallback; the plugin does not label it as a particular NextDNS profile.

## Profiles

Use **Add profile** beside **Refresh** to reveal the name and ID fields below the saved-profile list. Use the pencil button to edit an entry and the × button to remove it from the list. The editor stays collapsed until requested. Removing an entry does not delete the profile from NextDNS or change the currently active profile. Profile IDs are read from the NextDNS Setup page and are not API keys.

## Security

Read-only status commands run as the desktop user. Mutating commands are direct `pkexec nextdns …` argument arrays—no password is stored and user-supplied profile IDs are validated before use. Package installation runs only after the user presses the install button and remains visible in a terminal.

## Removal

Removing this bar plugin does not uninstall or deactivate NextDNS:

```sh
omarchy plugin remove bitshaker.nextdns-omarchy
```

Manage or uninstall the CLI separately if desired.
