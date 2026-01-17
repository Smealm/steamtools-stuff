
# Steam NoCloud Script

This PowerShell script automatically updates Steam `sharedconfig.vdf` files for all Steam user profiles on the current machine. It scans your Steam library for installed games and adds them to the `apps` block with `cloudenabled` set to `0`, effectively disabling cloud saves for those apps.

---

## What it does

### 1. Finds Steam install path
Reads the Steam installation location from the Windows registry.

### 2. Extracts App IDs
Reads `libraryfolders.vdf` and extracts all App IDs from your Steam libraries.

### 3. Detects Lua plugins
Checks which App IDs have Lua plugins stored in:

```

%SteamPath%\config\stplug-in

````

### 4. Updates `sharedconfig.vdf`
For every Steam user folder, it:

- Finds `sharedconfig.vdf`
- Replaces or inserts an `"apps"` block
- Adds missing App IDs with `cloudenabled "0"`
- Cleans up formatting and duplicate blocks

---

## Requirements

- Windows PowerShell (recommended v5+)
- Steam installed on the PC
- Script must be run with sufficient permissions to edit Steam config files

---

## Notes

- This script modifies Steam configuration files.
- It is intended for disabling Steam Cloud for all detected apps.
- It does not uninstall or modify games.

---

## Run Command

Use this command to run the script directly from GitHub:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest 'https://raw.githubusercontent.com/Smealm/steamtools-stuff/refs/heads/main/steamtools-nocloud.ps1' -UseBasicParsing | Invoke-Expression"
````

---

## Alternative: Download & Run

1. Download the script:

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/Smealm/steamtools-stuff/refs/heads/main/steamtools-nocloud.ps1' -OutFile .\steamtools-nocloud.ps1
```

2. Run it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\steamtools-nocloud.ps1
```

---

## Troubleshooting

* If Steam is installed in a non-standard location, ensure the registry value exists.
* If no `sharedconfig.vdf` files are found, make sure Steam has at least one user profile.

---

## License

Use and modify freely.
