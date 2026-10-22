#!/bin/sh
# iOS only accepts URL schemes from the built Info.plist. Read REVERSED_CLIENT_ID
# from GoogleService-Info.plist and register it there. A missing plist is normal.
set -eu
PLIST="${SRCROOT}/Magazinchik/GoogleService-Info.plist"
INFO="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ] || [ ! -f "$INFO" ]; then
  exit 0
fi
REVERSED="$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$PLIST" 2>/dev/null || true)"
if [ -z "$REVERSED" ] || [ "${REVERSED#YOUR_}" != "$REVERSED" ]; then
  exit 0
fi
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$INFO" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$INFO"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$INFO"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ${REVERSED}" "$INFO"
echo "Registered Google URL scheme"
