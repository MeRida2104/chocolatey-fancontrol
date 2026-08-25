$ErrorActionPreference = 'Stop'

if (-not (Get-OSArchitectureWidth 64) -or $env:chocolateyForceX86 -eq 'true') {
  throw 'FanControl requires a 64-bit installation of Windows.'
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/Rem0o/FanControl.Releases/releases/download/V275/FanControl_275_net_10_0_Installer.exe'
  checksum64     = '3c7acf6b6323b7f33511d88a12e5f97ccac32a8edb074555b0745ff196f5e8a6'
  checksumType64 = 'sha256'

  softwareName   = 'FanControl*'

  # Inno Setup
  silentArgs     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /FORCECLOSEAPPLICATIONS /LOG=`"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).InnoInstall.log`""
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs
