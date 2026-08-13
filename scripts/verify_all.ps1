# verify_all.ps1 — run the full verification matrix for moon-content-disposition.
#
#   * build the library
#   * run the test suite on native, js and wasm-gc
#   * smoke-test the CLI on all three targets
#   * smoke-test all six examples on the native target
#
# The moon executable is resolved from $env:MOON_BIN first, then from PATH,
# then from the known local install at D:\Moonbit\bin\moon.exe (the sibling
# `moon` file in that directory is a 0-byte shadow, so the .exe is used).
#
# Exit code 0 when everything passes; 1 otherwise. Summary lines are printed
# with [PASS] / [FAIL] prefixes so the report can be grepped.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Find-Moon {
  if ($env:MOON_BIN -and (Test-Path $env:MOON_BIN)) { return $env:MOON_BIN }
  $onPath = Get-Command moon.exe -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  $known = 'D:\Moonbit\bin\moon.exe'
  if (Test-Path $known) { return $known }
  throw "moon executable not found. Set `$env:MOON_BIN or add moon.exe to PATH."
}

$moon = Find-Moon
Write-Host "Using moon: $moon"
Write-Host "Root:      $root"
Write-Host ""

Set-Location $root

$fail = 0

function Run-Check {
  param([string]$Label, [string[]]$CmdArgs)
  Write-Host "---- $Label ----"
  & $moon @CmdArgs
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[PASS] $Label"
  } else {
    Write-Host "[FAIL] $Label (exit $LASTEXITCODE)"
    $script:fail = 1
  }
  Write-Host ""
}

# --- build -------------------------------------------------------------
Run-Check 'build (library)' @('build')

# --- tests -------------------------------------------------------------
Run-Check 'test native'      @('test')
Run-Check 'test js'          @('test', '--target', 'js')
Run-Check 'test wasm-gc'     @('test', '--target', 'wasm-gc')

# --- CLI smoke tests (all three targets) --------------------------------
$value = 'attachment; filename="report.pdf"; size=1024'
foreach ($target in @('native', 'js', 'wasm-gc')) {
  Run-Check "cli version ($target)" @('run', 'cmd/disposition-tool', '--target', $target, '--', 'version')
  Run-Check "cli parse ($target)"   @('run', 'cmd/disposition-tool', '--target', $target, '--', 'parse', $value)
  Run-Check "cli help ($target)"    @('run', 'cmd/disposition-tool', '--target', $target, '--', 'help')
}

# --- examples (native) --------------------------------------------------
foreach ($ex in @('parse', 'resolve', 'sanitize', 'generate', 'canonicalize', 'audit')) {
  Run-Check "example $ex" @('run', "examples/$ex")
}

# --- summary ------------------------------------------------------------
Write-Host "=================================================="
if ($fail -eq 0) {
  Write-Host "ALL CHECKS PASSED"
} else {
  Write-Host "SOME CHECKS FAILED"
}
Write-Host "=================================================="
exit $fail
