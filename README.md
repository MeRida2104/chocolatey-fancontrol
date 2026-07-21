# chocolatey-fancontrol

Chocolatey packaging for [Fan Control](https://getfancontrol.com/) by Rémi Mercier (Rem0o).

Package on the community repository: <https://community.chocolatey.org/packages/fancontrol>

## What this repository is

This repository contains **only the packaging scripts**. It contains no Fan Control
binaries — Fan Control is proprietary freeware and may not be redistributed. The
package downloads the official installer from the vendor's GitHub release at install
time and verifies its SHA256 checksum.

## Layout

| Path | Purpose |
| --- | --- |
| `fancontrol.nuspec` | Package metadata |
| `tools/chocolateyinstall.ps1` | Downloads and silently runs the official installer |
| `tools/chocolateybeforemodify.ps1` | Stops a running Fan Control before upgrade/uninstall |
| `icons/fancontrol.png` | Icon referenced by `iconUrl` via jsDelivr |

## Building

```powershell
choco pack
choco install fancontrol -s . -y   # test in a VM
choco uninstall fancontrol -y
choco push fancontrol.<version>.nupkg -s https://push.chocolatey.org/
```

## Updating to a new upstream release

1. Look up the new release at <https://github.com/Rem0o/FanControl.Releases/releases>.
2. Bump `<version>` in the nuspec (upstream `V271` becomes `271.0.0`).
3. Update the URL, the SHA256 checksum and `<releaseNotes>`.
4. Verify that the required .NET runtime dependency still matches the build.

## License

The packaging scripts in this repository are provided as-is. Fan Control itself is
licensed by its author; see the [upstream license](https://github.com/Rem0o/FanControl.Releases/blob/master/LICENSE).
This repository is not affiliated with or endorsed by Rémi Mercier.
