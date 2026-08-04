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
| `test/New-SandboxConfig.ps1` | Generates a Windows Sandbox config for this checkout |
| `test/Test-Package.ps1` | The actual install/uninstall test |
| `test/Run-Test.cmd` | Wrapper so the ExecutionPolicy never gets in the way |

## Building

The whole cycle at a glance:

```powershell
choco pack                                                              # -> fancontrol.<version>.nupkg
choco install fancontrol -s . -y                                        # VM only, never your workstation
choco uninstall fancontrol -y
choco push fancontrol.<version>.nupkg -s https://push.chocolatey.org/
```

`choco pack` reads `fancontrol.nuspec` and packs `tools\**` into the nupkg. It stays
tiny (a few kB) because no binaries are embedded — if it ever comes out at tens of
megabytes, something is being bundled that must not be.

The install and uninstall lines above are the crude version. Use the sandbox described
below instead: it asserts the outcome rather than leaving you to eyeball it, and it
cannot wreck the machine you are working on.

## Testing

Never test this on your working machine: the package installs a driver-touching
hardware utility and the point of the exercise is to watch it install and uninstall
cleanly. **Windows Sandbox** is the cheapest way to get a throwaway machine — it needs
no product key or ISO, since Windows Pro, Enterprise and Education include the
entitlement, and it resets completely every time you close it.

Enable it once, from an elevated PowerShell, then reboot:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

Then build the package, generate a sandbox config for your checkout and launch it:

```powershell
choco pack
.\test\New-SandboxConfig.ps1 -Start
```

The sandbox mounts the repository read-only at `C:\pkg` and runs the test on logon.
`New-SandboxConfig.ps1` exists because Windows Sandbox does not support relative paths
in `<MappedFolders>`, so the config has to be written for wherever the repository sits.
The generated `.wsb` is git-ignored.

### What the test asserts

**Phase 1** installs with `--ignore-dependencies`, exercising this package alone:

- `choco install` succeeds and Fan Control lands in `C:\Program Files\FanControl`
- An uninstall entry is registered, so Chocolatey's auto-uninstaller has something to work with
- The shipped build is still framework-dependent and still asks for
  `Microsoft.WindowsDesktop.App` — if upstream ever switches to a self-contained build,
  this fails and tells you to drop the runtime dependency from the nuspec
- The major version that `FanControl.runtimeconfig.json` demands matches the
  `dotnet-<major>.0-desktopruntime` dependency declared in the nuspec
- Uninstalling leaves neither the registry entry nor the program folder behind

**Phase 2** repeats the install with dependencies, which is what a real user gets.

### Known snag: exit code 1618

The .NET Desktop Runtime ships as a WiX Burn bundle and takes the global
`_MSIExecute` mutex. A freshly booted machine is often still finishing its own
installer transactions, and the runtime then fails with `1618`
(`ERROR_INSTALL_ALREADY_RUNNING`). The test waits for that mutex to stay free for a
stretch and retries, but if it persists, restart the sandbox and run it again.

Two things inside the sandbox are expected and not worth chasing: Windows reports
itself as **not activated** (the sandbox image is a volume-license SKU with no
activation path), and Fan Control itself will not find any fans, because there is no
real sensor hardware. Neither affects what is being tested here.

## Publishing

```powershell
choco push fancontrol.<version>.nupkg -s https://push.chocolatey.org/
```

While a version is still in moderation it can be fixed and pushed again under the
same version number — it moves to "Updated" at the top of the queue rather than
losing its place.

## Updating to a new upstream release

Upstream tags releases as `V271`, `V272` and so on. Chocolatey needs three-part
versions, so `V271` becomes `271.0.0`.

**1. Find the release and its assets.**

```powershell
$r = Invoke-RestMethod https://api.github.com/repos/Rem0o/FanControl.Releases/releases/latest
$r.tag_name
$r.assets | Select-Object name, size, browser_download_url
```

This package tracks the `net_10_0` **installer** asset, not the portable zip.

**2. Work out the new checksum.** Chocolatey requires one for every download, and it
has to be computed from the file itself:

```powershell
$v   = '272'                                          # new upstream version
$url = "https://github.com/Rem0o/FanControl.Releases/releases/download/V$v/FanControl_${v}_net_10_0_Installer.exe"
$tmp = "$env:TEMP\fancontrol-installer.exe"
Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
(Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
Get-AuthenticodeSignature $tmp | Select-Object Status, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

The signature check is worth the extra line — releases are signed by
`CN=Rémi Mercier`, and a broken or missing signature means the download is not what it
should be.

**3. Edit the two files.**

| File | Change |
| --- | --- |
| `fancontrol.nuspec` | `<version>`, `<releaseNotes>` |
| `tools/chocolateyinstall.ps1` | `url64bit`, `checksum64` |

**4. Check the silent arguments still apply.** They are Inno Setup switches. If a
release ever ships a different installer technology, `/VERYSILENT` stops working and
the install will hang instead of failing loudly:

```powershell
$bytes = [IO.File]::ReadAllBytes($tmp)
if ([Text.Encoding]::ASCII.GetString($bytes) -match 'Inno Setup Setup Data \(([\d\.a-z]+)\)') { $Matches[0] }
```

**5. Pack and test.**

```powershell
choco pack
.\test\New-SandboxConfig.ps1 -Start
```

Wait for both phases to come back green in the sandbox. The test verifies on its own
that the declared .NET runtime dependency still matches what the new build actually
requires, so that is not something you have to remember to check by hand.

**6. Push.**

```powershell
choco push fancontrol.<version>.nupkg -s https://push.chocolatey.org/
```

Do not reuse a version number that has already been approved; bump it. Versions still
sitting in moderation are the exception and may be replaced in place.

## Vendor permission

Fan Control's [license](https://github.com/Rem0o/FanControl.Releases/blob/master/LICENSE)
does not grant redistribution rights, so permission was requested before publishing.
Rémi Mercier (Rem0o), the author and rights holder, granted it in
[FanControl.Releases#4105](https://github.com/Rem0o/FanControl.Releases/issues/4105#issuecomment-5036906935)
on 2026-07-21: "Fine by me. […] Go ahead."

Note that this package redistributes nothing regardless — it downloads the official,
Authenticode-signed installer straight from the vendor's GitHub release and verifies
its SHA256 checksum before running it.

## License

The packaging scripts in this repository are provided as-is. Fan Control itself is
proprietary freeware licensed by its author for personal, non-commercial use; see the
[upstream license](https://github.com/Rem0o/FanControl.Releases/blob/master/LICENSE).
This repository is maintained independently and is not an official distribution channel.
