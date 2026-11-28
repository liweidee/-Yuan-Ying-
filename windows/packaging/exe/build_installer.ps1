[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [string]$AppVersion,

    [Parameter(Mandatory = $true)]
    [string]$BuildNumber,

    [Parameter(Mandatory = $true)]
    [string]$RunNumber,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$IsccPath = "",

    [switch]$GenerateOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))

function Resolve-RepoPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Get-ConfigValue([string]$ConfigPath, [string]$Name) {
    $pattern = "(?m)^$([Regex]::Escape($Name)):\s*(.+?)\s*$"
    $match = [Regex]::Match((Get-Content -LiteralPath $ConfigPath -Raw), $pattern)
    if (-not $match.Success) {
        throw "make_config.yaml 缺少字段: $Name"
    }
    return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

function Resolve-Iscc([string]$Hint) {
    $candidates = @(
        $Hint,
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 7\ISCC.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    throw "未找到 ISCC.exe，请先安装 Inno Setup 6。"
}

$sourcePath = Resolve-RepoPath $SourceDir
if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    throw "Windows Release 目录不存在: $sourcePath"
}

$executablePath = Join-Path $sourcePath "yuanying.exe"
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "未找到 Windows 主程序: $executablePath"
}

$outputPath = Resolve-RepoPath $OutputDir
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$configPath = Join-Path $PSScriptRoot "make_config.yaml"
$templatePath = Join-Path $PSScriptRoot "inno_setup.iss"
$appId = Get-ConfigValue $configPath "app_id"
$publisher = Get-ConfigValue $configPath "publisher"
$publisherUrl = Get-ConfigValue $configPath "publisher_url"
$displayName = Get-ConfigValue $configPath "display_name"
$privileges = Get-ConfigValue $configPath "privileges_required"

$displayVersion = "$AppVersion+$BuildNumber"
$numericVersion = "$AppVersion.$BuildNumber"
$outputBaseName = "yuanying-windows-x64-v$displayVersion-r$RunNumber"
$setupIcon = Resolve-RepoPath "windows\runner\resources\app_icon.ico"
$languageFile = Join-Path $PSScriptRoot "ChineseSimplified.isl"
if (-not (Test-Path -LiteralPath $languageFile -PathType Leaf)) {
    throw "缺少 Inno Setup 简体中文语言文件: $languageFile"
}

$content = Get-Content -LiteralPath $templatePath -Raw
$content = $content.Replace("AppId={{APP_ID}}", "AppId={{$appId}")
$content = $content.Replace("{{SOURCE_DIR}}\\*", "{{SOURCE_DIR}}\*")
$content = $content.Replace("{{APP_VERSION}}", $numericVersion)
$content = $content.Replace("{{DISPLAY_NAME}}", $displayName)
$content = $content.Replace("{{PUBLISHER_NAME}}", $publisher)
$content = $content.Replace("{{PUBLISHER_URL}}", $publisherUrl)
$content = $content.Replace("{{INSTALL_DIR_NAME}}", "{autopf}\Yuanying")
$content = $content.Replace("{{OUTPUT_BASE_FILENAME}}", $outputBaseName)
$content = $content.Replace("{{SETUP_ICON_FILE}}", $setupIcon)
$content = $content.Replace("{{PRIVILEGES_REQUIRED}}", $privileges)
$content = $content.Replace("{{SOURCE_DIR}}", $sourcePath)
$content = $content.Replace("{{EXECUTABLE_NAME}}", "yuanying.exe")
$content = $content.Replace(
    "compiler:Languages\ChineseSimplified.isl",
    $languageFile
)
$content = [Regex]::Replace(
    $content,
    "(?m)^OutputDir=.*$",
    "OutputDir=$outputPath"
)

if ($content -match "\{\{[A-Z0-9_]+\}\}") {
    throw "Inno Setup 模板仍有未替换变量: $($Matches[0])"
}

$issPath = Join-Path $outputPath "$outputBaseName.iss"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($issPath, $content, $utf8Bom)

if ($GenerateOnly) {
    Write-Output $issPath
    return
}

$resolvedIscc = Resolve-Iscc $IsccPath
& $resolvedIscc "/Q" $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup 编译失败，ISCC exit code: $LASTEXITCODE"
}

$installerPath = Join-Path $outputPath "$outputBaseName.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Inno Setup 未生成预期安装包: $installerPath"
}

Write-Output $installerPath
