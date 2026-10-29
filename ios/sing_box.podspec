#
# CocoaPods spec of the sing_box Flutter plugin (the app side). The Packet
# Tunnel extension uses the separate `SingBoxTunnel` pod. Swift Package Manager
# builds use sing_box/Package.swift instead.
#
require_relative 'libbox'

Pod::Spec.new do |s|
  s.name             = 'sing_box'
  s.version          = '1.1.0'
  s.summary          = 'Flutter VPN plugin powered by the sing-box core.'
  s.description      = <<-DESC
Flutter plugin running the sing-box core (libbox) in a Network Extension:
VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, routing rules,
statistics and speed tests.
                       DESC
  s.homepage         = 'https://github.com/QUSAD-prod/sing_box'
  s.license          = { :type => 'GPL-3.0-or-later', :file => '../LICENSE' }
  s.author           = { 'QUSAD-prod' => 'https://github.com/QUSAD-prod' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'

  s.source_files = [
    'sing_box/Sources/sing_box/**/*.swift',
    'sing_box/Sources/SingBoxShared/**/*.swift',
  ]
  # Members of libbox protocols that differ between the cores.
  s.exclude_files = SingBoxLibbox.other_core_sources
  s.resource_bundles = { 'sing_box_privacy' => ['sing_box/Sources/sing_box/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'

  s.vendored_frameworks = SingBoxLibbox.ensure!(__dir__)
  s.preserve_paths = SingBoxLibbox.framework
  s.frameworks = 'NetworkExtension', 'UserNotifications'
  # Go's runtime in libbox needs libresolv.
  s.libraries = 'resolv'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
