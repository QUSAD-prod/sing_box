#!/bin/sh
# `flutter test integration_test/...` may reinstall the example app, which resets
# the VPN consent. Keep this running while the e2e test runs.
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
while true; do
  "$ADB" shell appops set com.qusadprod.sing_box_example ACTIVATE_VPN allow >/dev/null 2>&1
  sleep 1
done
