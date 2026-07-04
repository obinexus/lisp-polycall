$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$nativeSource = Join-Path $root 'src/lisp_polycall.c'
$lispSource = Join-Path $root 'src/lisp-polycall.lisp'
$forbidden = 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\('
$matches = Select-String -Path $nativeSource,$lispSource -Pattern $forbidden

if ($matches) {
    $matches | ForEach-Object { Write-Error $_.Line }
    throw 'lisp-polycall must not parse configuration or implement runtime logic'
}

$adapter = Get-Content -Raw $nativeSource
$lisp = Get-Content -Raw $lispSource
if (-not $adapter.Contains('polycall_ffi_run_config(config_path, 1)')) {
    throw 'lisp-polycall does not forward through polycall_ffi_run_config'
}
if (-not $lisp.Contains('cffi:defcfun') -or
    -not $lisp.Contains('(config-path :string)')) {
    throw 'lisp-polycall does not declare its CFFI string boundary'
}
if (-not $lisp.Contains('cffi:*default-foreign-encoding* :utf-8')) {
    throw 'lisp-polycall does not marshal configuration paths as UTF-8'
}

Write-Output 'lisp-polycall thin-adapter check: PASS'
