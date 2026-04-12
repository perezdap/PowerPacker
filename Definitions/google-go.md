---
winget_id: Google.Go
name: Go Programming Language
version: 1.22.2
---

# Install
Install the Go programming language MSI silently. Ensure that the installer adds Go to the system PATH.

# Uninstall
Uninstall Go using its MSI product code. If the product code is not available, look for the uninstall string in the registry under 'Go Programming Language'.

# Detection
Verify that 'go.exe' exists in the default installation directory (usually 'C:\Program Files\Go\bin\go.exe') or check if the 'GOROOT' environment variable is set.
