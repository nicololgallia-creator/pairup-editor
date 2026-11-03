# Opening PairUp on Windows

PairUp is not signed with a paid certificate yet, so Windows SmartScreen may warn the first time.

1. Check the download. In PowerShell run `Get-FileHash .\PairUp-win32-x64-<version>.zip -Algorithm SHA256` and compare the result with the matching line in `SHA256SUMS`. If they differ, do not open it.
2. Right-click the zip, choose Properties, tick Unblock at the bottom, press OK. Then extract it.
3. Run `PairUp.exe`. If SmartScreen says "Windows protected your PC", press More info, then Run anyway.

This is a warning about an unknown publisher, not a block. A signing certificate would remove it, and costs money, so it waits for the owner.
