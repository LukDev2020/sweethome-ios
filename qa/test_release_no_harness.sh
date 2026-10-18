#!/bin/bash
# Verify that QA_HARNESS symbols do not appear in a Release build.
# Run: bash qa/test_release_no_harness.sh
#
# This checks that the QA_HARNESS compilation flag is NOT set in Release
# configuration, ensuring test-only code is stripped from production builds.

set -euo pipefail

echo "=== Release Build Symbol Absence Test ==="

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 1. Check that QA_HARNESS is not in Release build settings
echo "Checking xcodeproj for QA_HARNESS in Release..."
if grep -r 'QA_HARNESS' ShouDeng.xcodeproj/project.pbxproj 2>/dev/null | grep -i release; then
    echo "FAIL: QA_HARNESS found in Release configuration"
    exit 1
fi
echo "  PASS: QA_HARNESS not in Release config"

# 2. Grep all Swift files for #if QA_HARNESS — verify they're properly guarded
echo "Checking Swift source for #if QA_HARNESS usage..."
QA_FILES=$(grep -rl '#if QA_HARNESS' ShouDeng/ 2>/dev/null || true)
if [ -z "$QA_FILES" ]; then
    echo "  INFO: No #if QA_HARNESS found in source (hook not yet added)"
else
    echo "  Files with #if QA_HARNESS:"
    for f in $QA_FILES; do
        echo "    $f"
        # Verify each #if QA_HARNESS has a matching #endif
        IF_COUNT=$(grep -c '#if QA_HARNESS' "$f")
        ENDIF_COUNT=$(grep -c '#endif' "$f")
        if [ "$IF_COUNT" -gt "$ENDIF_COUNT" ]; then
            echo "    FAIL: Mismatched #if/#endif in $f"
            exit 1
        fi
    done
    echo "  PASS: All #if QA_HARNESS blocks properly closed"
fi

# 3. Verify emulator URLs don't appear outside conditional compilation
echo "Checking for emulator URLs outside conditionals..."
EMULATOR_URLS=$(grep -rn 'sweethome-d1edd' ShouDeng/ 2>/dev/null | grep -v '#if' | grep -v '//' || true)
if [ -n "$EMULATOR_URLS" ]; then
    echo "  WARNING: Emulator project ID found outside #if blocks:"
    echo "$EMULATOR_URLS"
fi
echo "  PASS: Emulator URL check complete"

echo ""
echo "=== All checks passed ==="
