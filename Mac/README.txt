MAAN MAC CLEAN REBUILD
======================

This package is a clean rebuild of the MAAN macOS side.
It does NOT use the old build_maan.sh target.

1. Open this Mac folder in Finder.
2. Double-click CHECK.command once.
3. Then double-click build_maan.command.

If macOS blocks a .command file:
- Right-click it -> Open -> Open.

Terminal alternative:
cd <this-folder>/Mac
chmod +x CHECK.command build_maan.command
./CHECK.command
./build_maan.command

IMPORTANT:
Do not compile MAANMacApp.swift directly with an old command.
Do not use the old build_maan.sh.
The new Package.swift explicitly links AppKit, Foundation, Network,
AVFoundation, UniformTypeIdentifiers and UserNotifications.

The actual Swift source is:
Sources/MAAN/main.swift
