# WinGet prerequisite for Intune

This Win32 app provisions Microsoft's App Installer package, which supplies `winget.exe`. It does not install or update any other applications.

## Package and deploy

1. Use Microsoft's Win32 Content Prep Tool to build a fresh `.intunewin` after changing the scripts; the existing `install.intunewin` is an older package and does not include the current scripts:

   ```text
   IntuneWinAppUtil.exe -c "<source-folder>" -s install.ps1 -o "<output-folder>"
   ```

   Set `<source-folder>` to this folder and keep `<output-folder>` outside it.
2. In Intune, use this install command:

   ```text
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
   ```

3. Set **Install behavior** to **System** and run the script in 64-bit PowerShell.
4. Configure `detection.ps1` as the custom detection script and run it in 64-bit PowerShell.

The installer downloads the current App Installer bundle and architecture-matched Microsoft VCLibs and UI.Xaml dependencies from `aka.ms`, then provisions them for the device. The device therefore needs access to those Microsoft download endpoints during installation. Installation and detection are both safe to rerun.

## Uninstall

Set the Intune Win32 app uninstall command to:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

Run it with **System** install behavior in 64-bit PowerShell. It removes App Installer (and therefore `winget.exe`) for all users and removes its device provisioning, then verifies removal. Shared VCLibs and UI.Xaml dependencies are left installed because other apps may use them. Uninstallation does not require downloading files.
