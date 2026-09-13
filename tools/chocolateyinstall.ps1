$ErrorActionPreference = 'Stop'

if (-not (Get-OSArchitectureWidth 64) -or $env:chocolateyForceX86 -eq 'true') {
  throw 'FanControl requires a 64-bit installation of Windows.'
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/Rem0o/FanControl.Releases/releases/download/V277/FanControl_277_net_10_0_Installer.exe'
  checksum64     = '85484d1a9cb1895ad8212d1232e03af35d749497b3429a08a5c32bbd2da8ebf9'
  checksumType64 = 'sha256'

  softwareName   = 'FanControl*'

  # Inno Setup
  silentArgs     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /FORCECLOSEAPPLICATIONS /LOG=`"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).InnoInstall.log`""
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs
