# Get Steam install path from registry
$steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
if (-not $steamPath) { Write-Error "Steam path not found in registry."; exit }

# -----------------------------
# 1. Read libraryfolders.vdf and get App IDs
# -----------------------------
$vdfPath = Join-Path $steamPath "config\libraryfolders.vdf"
if (-not (Test-Path $vdfPath)) { Write-Error "libraryfolders.vdf not found at $vdfPath"; exit }

$content = Get-Content $vdfPath -Raw
$appIdPattern = '"(\d+)"\s+"\d+"'
$appIds = [regex]::Matches($content, $appIdPattern) | ForEach-Object { $_.Groups[1].Value }

$totalApps = $appIds.Count

# -----------------------------
# 2. Check which App IDs have Lua plugins
# -----------------------------
$pluginPath = Join-Path $steamPath "config\stplug-in"
$luaAppIds = @()
foreach ($id in $appIds) {
    if (Test-Path (Join-Path $pluginPath "$id.lua")) {
        $luaAppIds += $id
    }
}

$luaCount = $luaAppIds.Count

Write-Output "Total App IDs: $totalApps"
Write-Output "App IDs with Lua: $luaCount"

# -----------------------------
# 3. Update sharedconfig.vdf, replace or add "apps"
# -----------------------------
$userdataPath = Join-Path $steamPath "userdata"
$sharedConfigs = Get-ChildItem -Path $userdataPath -Recurse -Filter sharedconfig.vdf |
                 Where-Object { $_.FullName -match '\\7\\remote\\' }

foreach ($file in $sharedConfigs) {

    $content = Get-Content $file.FullName -Raw

    # -----------------------------
    # Detect existing App IDs to avoid duplicates
    # -----------------------------
    $existingAppIds = @()
    $appsMatchExisting = [regex]::Match($content, '"apps"\s*{(.*?)}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($appsMatchExisting.Success) {
        $appsContent = $appsMatchExisting.Groups[1].Value
        $existingAppIds = [regex]::Matches($appsContent, '"(\d+)"\s*{') | ForEach-Object { $_.Groups[1].Value }
    }

    # Filter Lua App IDs to insert only new ones
    $luaAppIdsToInsert = $luaAppIds | Where-Object { $existingAppIds -notcontains $_ }

    # -----------------------------
    # Build apps block with proper alignment
    # -----------------------------
    $appsBlock = "`t`t`t`t""apps""`n`t`t`t`t{`n"  # 4 tabs for "apps" line
    foreach ($id in $luaAppIdsToInsert) {
        $appsBlock += "`t`t`t`t`t""$id""`n`t`t`t`t`t{`n`t`t`t`t`t`t""cloudenabled""`t`t""0""`n`t`t`t`t`t}`n"
    }
    $appsBlock += "`t`t`t`t}`n"

    # -----------------------------
    # Replace existing "apps" block or insert if missing
    # -----------------------------
    if ($content -match '"apps"\s*{') {
        Write-Output "User $($file.DirectoryName) : replacing existing 'apps' block"

        # Regex to fully match entire "apps" block including nested App IDs
        $appsPattern = '"apps"\s*{(?:[^{}]*|{[^{}]*})*}'
        $content = [regex]::Replace($content, $appsPattern, $appsBlock, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        Write-Output "User $($file.DirectoryName) : adding new 'apps' block"
        if ($content -match '("cloudenabled"\s*"\d+")') {
            $content = $content -replace '("cloudenabled"\s*"\d+")', "$appsBlock`$1"
        } else {
            $content = $content -replace '(("Steam"\s*{))', "`$1`n$appsBlock"
        }
    }

    # -----------------------------
    # Post-process: fix "apps" indentation
    # -----------------------------
    $content = [regex]::Replace($content, '^\t+"apps"', "`t`t`t`t""apps""", [System.Text.RegularExpressions.RegexOptions]::Multiline)

    # -----------------------------
    # Post-process: remove stray App ID blocks after apps block safely
    # -----------------------------
    $appsMatch = [regex]::Match($content, '"apps"\s*{.*?^\t{4}}', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($appsMatch.Success) {
        $appsEndIndex = $appsMatch.Index + $appsMatch.Length
        $beforeApps = $content.Substring(0, $appsEndIndex)
        $afterApps = $content.Substring($appsEndIndex)

        # Split the remaining content into lines
        $lines = $afterApps -split "`r?`n"

        # Track open braces so we only remove top-level stray App ID blocks
        $braceLevel = 0
        $skip = $false
        $cleanLines = @()
        foreach ($line in $lines) {
            if ($line -match '{') { $braceLevel++ }
            if ($line -match '}') { $braceLevel-- }

            # Remove only top-level lines that start with a digit (App ID) outside any braces
            if ($braceLevel -eq 0 -and $line -match '^\s*"\d+"\s*{') {
                $skip = $true
                continue
            }

            # If skipping, check if current line is the closing brace for the App ID block
            if ($skip) {
                if ($line -match '^\s*}') {
                    $skip = $false
                }
                continue
            }

            $cleanLines += $line
        }

        # Recombine content
        $afterAppsClean = ($cleanLines -join "`n")
        $content = $beforeApps + $afterAppsClean
    }

    # -----------------------------
    # Post-process: remove a single extra closing brace if present
    # -----------------------------
    $content = [regex]::Replace($content, '(\t*\})\s*(\t*\})', '$1', [System.Text.RegularExpressions.RegexOptions]::Multiline)

    # -----------------------------
    # Post-process: ensure apps block ends with closing brace before "cloudenabled"
    # -----------------------------
    $appsMatch = [regex]::Match($content, '"apps"\s*{.*?^\t{4}"cloudenabled"', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($appsMatch.Success) {
        $appsBlockText = $appsMatch.Value

        # Count opening and closing braces in the apps block
        $openBraces  = ($appsBlockText | Select-String -AllMatches '{').Matches.Count
        $closeBraces = ($appsBlockText | Select-String -AllMatches '}').Matches.Count

        # If more opening braces than closing braces, insert missing closing brace(s)
        if ($openBraces -gt $closeBraces) {
            $missing = $openBraces - $closeBraces
            $closing = ("`t`t`t`t}`n" * $missing)  # 4 tabs for apps block closing

            # Split content into lines
            $lines = $content -split "`r?`n"
            $newLines = @()
            foreach ($line in $lines) {
                # Before the top-level cloudenabled line after apps, insert the missing braces
                if ($line -match '^\t{4}"cloudenabled"\s*"\d+"') {
                    $newLines += $closing
                }
                $newLines += $line
            }

            $content = ($newLines -join "`n")
        }
    }

    # -----------------------------
    # Save updated file
    # -----------------------------
    Set-Content -Path $file.FullName -Value $content -Encoding UTF8
}
