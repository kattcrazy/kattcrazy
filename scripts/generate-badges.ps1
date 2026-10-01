# Rewrite badges/*.json from PROJECT-DIRECTORY.md.
# Used by the GitHub workflow and by sync.ps1. Does not edit any README.
# Usage:
#   pwsh -File scripts/generate-badges.ps1 -Directory PROJECT-DIRECTORY.md -BadgeDir badges

param(
    [string]$Directory,
    [string]$BadgeDir
)

$ErrorActionPreference = "Stop"

$ColorHex = @{
    ([char]::ConvertFromUtf32(0x1F7E5)) = "E23B3B"
    ([char]::ConvertFromUtf32(0x1F7E7)) = "F0883E"
    ([char]::ConvertFromUtf32(0x1F7E9)) = "3FB950"
    ([char]::ConvertFromUtf32(0x1F7E6)) = "15BCF2"
}
$SectionColor = "6959F6"

function New-BadgePathMap {
    return New-Object "System.Collections.Generic.Dictionary[string,string]" ([StringComparer]::Ordinal)
}

function Read-ProjectDirectory {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $labels = @{}
    $section = $null
    $projects = @()
    $seen = @{}

    foreach ($line in ($text -split "\r?\n")) {
        foreach ($emoji in @($ColorHex.Keys)) {
            if ($line.Contains($emoji) -and $line -match "=\s*(.+)$") {
                $labels[$emoji] = $Matches[1].Trim()
            }
        }
        if ($line -match "^##\s+(.+)$") {
            $section = $Matches[1].Trim()
            continue
        }
        if ($line -notmatch "https://github\.com/kattcrazy/([^)\s]+)") {
            continue
        }
        $repo = $Matches[1].TrimEnd("/")
        if ($repo.EndsWith(".git")) {
            $repo = $repo.Substring(0, $repo.Length - 4)
        }
        if (-not $section) {
            throw "Repo $repo is above any status heading"
        }
        $found = @()
        foreach ($emoji in @($ColorHex.Keys)) {
            if ($line.Contains($emoji)) {
                $found += $emoji
            }
        }
        if ($found.Count -ne 1) {
            throw "Repo $repo needs exactly one colour-key emoji"
        }
        $emoji = $found[0]
        if (-not $labels.ContainsKey($emoji)) {
            throw "Colour $emoji has no label in the emoji key"
        }
        if ($seen.ContainsKey($repo)) {
            throw "Repo $repo is listed twice"
        }
        $seen[$repo] = $true
        $sectionMessage = $null
        if ($section -ne "Maintaining") {
            $sectionMessage = $section
        }
        $projects += [pscustomobject]@{
            Repo = $repo
            ColorMessage = $labels[$emoji]
            Color = $ColorHex[$emoji]
            SectionMessage = $sectionMessage
        }
    }

    foreach ($emoji in @($ColorHex.Keys)) {
        if (-not $labels.ContainsKey($emoji)) {
            throw "Emoji key is missing a label for $emoji"
        }
    }
    return @($projects)
}

function Get-BadgeJson {
    param([string]$BadgeMessage, [string]$Color)
    $escaped = $BadgeMessage.Replace("\", "\\").Replace('"', '\"')
    $lines = @(
        "{",
        "  `"schemaVersion`": 1,",
        "  `"label`": `"`",",
        "  `"message`": `"$escaped`",",
        "  `"color`": `"$Color`",",
        "  `"labelColor`": `"$Color`",",
        "  `"style`": `"for-the-badge`",",
        "  `"cacheSeconds`": 300",
        "}"
    )
    return (($lines -join "`n") + "`n")
}

function Get-ProjectBadgeFiles {
    param($Projects)
    $files = New-BadgePathMap
    foreach ($project in $Projects) {
        $files["badges/$($project.Repo).json"] = Get-BadgeJson $project.ColorMessage $project.Color
        if ($project.SectionMessage) {
            $files["badges/$($project.Repo)-section.json"] = Get-BadgeJson $project.SectionMessage $SectionColor
        }
    }
    return $files
}

function Update-BadgeFiles {
    param(
        [string]$Directory,
        [string]$BadgeDir
    )
    if (-not (Test-Path -LiteralPath $Directory)) {
        throw "Directory file missing: $Directory"
    }
    $projects = Read-ProjectDirectory $Directory
    if ($projects.Count -eq 0) {
        throw "No GitHub repos found in $Directory"
    }
    $files = Get-ProjectBadgeFiles $projects
    if (-not (Test-Path -LiteralPath $BadgeDir)) {
        New-Item -ItemType Directory -Path $BadgeDir | Out-Null
    }
    $keep = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::Ordinal)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    foreach ($path in @($files.Keys)) {
        $name = Split-Path -Path $path -Leaf
        [void]$keep.Add($name)
        $target = Join-Path $BadgeDir $name
        [System.IO.File]::WriteAllText($target, [string]$files[$path], $utf8)
        Write-Host "wrote $name"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $BadgeDir -Filter *.json -File)) {
        if (-not $keep.Contains($item.Name)) {
            Remove-Item -LiteralPath $item.FullName -Force
            Write-Host "removed $($item.Name)"
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    if (-not $Directory -or -not $BadgeDir) {
        throw "Pass -Directory and -BadgeDir"
    }
    Update-BadgeFiles -Directory $Directory -BadgeDir $BadgeDir
}
