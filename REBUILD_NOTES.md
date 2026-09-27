# MAAN clean rebuild

The reported errors were all AppKit symbols (`NSWindow`, `NSView`, `NSPanel`, `NSOpenPanel`, `NSApp`, `NSImage`, `NSPasteboard`, `NSFilePromiseProvider`, etc.) being unavailable even though the intended source imports AppKit. The clean package avoids the old ad-hoc build target and uses `Package.swift` with explicit AppKit linker settings.

The source parses successfully with the Swift frontend in the development environment. Native AppKit linking/runtime cannot be performed here because the environment is not macOS.

The package keeps the existing MAAN transport server and current Mac UI/call/screen/file/clipboard implementation instead of changing the protocol.
