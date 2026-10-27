# iOS agent notes (ios/**, example/ios/**)

Status: STARTED (2026-10-27) — reading contract, libbox headers, SFI reference.

## Next steps
1. Read libbox 1.14.4 ObjC header, SFI ExtensionProvider/PlatformInterface/CommandClient.
2. Write ios/sing_box/Package.swift + Sources (SingBoxShared, SingBoxTunnel, sing_box plugin).
3. Podspecs (sing_box.podspec, SingBoxTunnel.podspec) with libbox download logic.
4. example/ios PacketTunnel target (xcodeproj ruby script ios/scripts/add_packet_tunnel.rb).
5. Builds SPM + CocoaPods, simulator harness.
