# install.ps1: envoltorio de install.sh para Windows. SIN VERIFICAR: no se ha ejecutado nunca
# (no habia PowerShell donde se escribio). Toda la logica esta en install.sh; esto solo
# busca Git Bash, fija P4_COPY=1 (modo copia), traduce las opciones y devuelve el codigo
# de salida de install.sh. Uso: .\install.ps1 [-DryRun] [-Adopt] [-NonInteractive]
param([switch]$DryRun, [switch]$Adopt, [switch]$NonInteractive)

# Git Bash: junto a git.exe (...\Git\cmd\git.exe -> ...\Git\bin\bash.exe) o en la ruta tipica.
$bash = $null
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
  $c = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
  if (Test-Path $c) { $bash = $c }
}
if (-not $bash -and (Test-Path 'C:\Program Files\Git\bin\bash.exe')) { $bash = 'C:\Program Files\Git\bin\bash.exe' }
if (-not $bash) {
  [Console]::Error.WriteLine('error: no se encontro Git Bash (bin\bash.exe de Git for Windows); instale Git for Windows y repita')
  exit 3
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine('error: no se encontro node en el PATH; instale Node.js y repita')
  exit 3
}

$a = @()
if ($DryRun) { $a += '--dry-run' }
if ($Adopt) { $a += '--adopt' }
if ($NonInteractive) { $a += '--non-interactive' }
# $rc empieza en 1: si algo lanza una excepcion antes de terminar, no se devuelve 0.
# P4_COPY vuelve a su valor anterior al salir.
$rc = 1
$prevCopy = $env:P4_COPY
$env:P4_COPY = '1'
Push-Location $PSScriptRoot
try {
  & $bash ./install.sh @a
  $rc = $LASTEXITCODE
} finally {
  Pop-Location
  $env:P4_COPY = $prevCopy
}
exit $rc
