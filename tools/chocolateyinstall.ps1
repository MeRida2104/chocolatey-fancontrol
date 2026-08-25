$ErrorActionPreference = 'Stop'

if (-not (Get-OSArchitectureWidth 64) -or $env:chocolateyForceX86 -eq 'true') {
  throw 'FanControl requires a 64-bit installation of Windows.'
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/Rem0o/FanControl.Releases/releases/download/V274/FanControl_274_net_10_0_Installer.exe'
  checksum64     = 'a6811c2ee9917cc7d2628804c808572955815c4eef53cfd156bd615dae4125c3'
  checksumType64 = 'sha256'

  softwareName   = 'FanControl*'

  # Inno Setup
  silentArgs     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /FORCECLOSEAPPLICATIONS /LOG=`"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).InnoInstall.log`""
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs
