$ErrorActionPreference = 'Stop'

if (-not (Get-OSArchitectureWidth 64) -or $env:chocolateyForceX86 -eq 'true') {
  throw 'FanControl requires a 64-bit installation of Windows.'
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/Rem0o/FanControl.Releases/releases/download/V273/FanControl_273_net_10_0_Installer.exe'
  checksum64     = 'f7cf5bc21b01239841af0af80c93fb74b9c6d6a04e73ebf1301b043c5015e8cb'
  checksumType64 = 'sha256'

  softwareName   = 'FanControl*'

  # Inno Setup
  silentArgs     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /FORCECLOSEAPPLICATIONS /LOG=`"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).InnoInstall.log`""
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs
