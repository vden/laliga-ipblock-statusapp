#!/bin/bash
# Runs the offline checks in Tests/ against Sources/BlockStatus.swift.
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build
swiftc Sources/BlockStatus.swift Tests/main.swift -swift-version 6 -o build/tests
build/tests
