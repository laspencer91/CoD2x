[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$ToolchainDirectory,
    [string]$CMake = 'cmake',
    [string]$Ninja = 'ninja',
    [string]$MsysDirectory = 'C:\msys64',
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$toolchain = (Resolve-Path -LiteralPath $ToolchainDirectory).Path
$compilerDirectory = Join-Path $toolchain 'mingw32\bin'
$cCompiler = Join-Path $compilerDirectory 'gcc.exe'
$cppCompiler = Join-Path $compilerDirectory 'g++.exe'
$assembler = Join-Path $toolchain 'usr\bin\nasm.exe'
$cmakePath = (Get-Command $CMake -ErrorAction Stop).Source
$ninjaPath = (Get-Command $Ninja -ErrorAction Stop).Source
foreach ($path in @($cCompiler, $cppCompiler, $assembler, (Join-Path $source 'tools\openssl_mingw\lib\libcrypto.a'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing bridge build input: $path" }
}
$build = Join-Path $PSScriptRoot 'build\bridge'
$previousPath = $env:PATH
try {
    $env:PATH = "$compilerDirectory;$(Join-Path $toolchain 'usr\bin');$(Join-Path $MsysDirectory 'usr\bin');$previousPath"
    & $cmakePath -S $source -B $build -G Ninja '-DCMAKE_BUILD_TYPE=RelWithDebInfo' '-DCOD2X_SMOKE_TEST_BUILD=ON' `
        "-DCMAKE_MAKE_PROGRAM=$ninjaPath" "-DCMAKE_C_COMPILER=$cCompiler" "-DCMAKE_CXX_COMPILER=$cppCompiler" `
        "-DCMAKE_ASM_NASM_COMPILER=$assembler"
    if ($LASTEXITCODE) { throw 'CoD2x bridge configuration failed.' }
    & $cmakePath --build $build --target mss32 --parallel 4
    if ($LASTEXITCODE) { throw 'CoD2x bridge build failed.' }
} finally { $env:PATH = $previousPath }
if (-not $BuildOnly) {
    & (Join-Path $PSScriptRoot 'Package-Test.ps1') -BridgeDll (Join-Path $source 'bin\windows\mss32.build.dll')
}
Write-Output 'Local test build completed. No game was installed, launched or uploaded.'
