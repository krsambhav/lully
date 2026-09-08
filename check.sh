#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc Sources/Lully/Assistant.swift Sources/Lully/Conversation.swift Sources/Lully/Cloud.swift Sources/Lully/Realtime.swift Sources/Lully/Capture.swift Sources/Lully/Shortcuts.swift Sources/Lully/WindowMovement.swift Sources/Lully/WindowResize.swift checks/main.swift -o .build/lully-checks
.build/lully-checks
