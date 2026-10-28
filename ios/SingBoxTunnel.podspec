#
# CocoaPods spec of the Packet Tunnel provider library for the host app's
# Network Extension target (no Flutter dependency):
#
#   target 'PacketTunnel' do
#     use_frameworks!
#     pod 'SingBoxTunnel', :path => '.symlinks/plugins/sing_box/ios'
#   end
#
# The extension's principal class is `class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`.
#
require_relative 'libbox'

Pod::Spec.new do |s|
  s.name             = 'SingBoxTunnel'
  s.version          = '1.0.0'
  s.summary          = 'Packet Tunnel provider of the sing_box Flutter plugin.'
  s.description      = <<-DESC
NEPacketTunnelProvider subclass running the sing-box core (libbox) for the
sing_box Flutter plugin. Link it into the app's Network Extension target.
                       DESC
  s.homepage         = 'https://github.com/QUSAD-prod/sing_box'
  s.license          = { :type => 'GPL-3.0-or-later', :file => '../LICENSE' }
  s.author           = { 'QUSAD-prod' => 'https://github.com/QUSAD-prod' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'

  s.source_files = [
    'sing_box/Sources/SingBoxTunnel/**/*.swift',
    'sing_box/Sources/SingBoxShared/**/*.swift',
  ]
  s.resource_bundles = { 'SingBoxTunnel_privacy' => ['sing_box/Sources/SingBoxTunnel/PrivacyInfo.xcprivacy'] }

  s.vendored_frameworks = SingBoxLibbox.ensure!(__dir__)
  s.preserve_paths = 'sing_box/Frameworks/Libbox.xcframework'
  s.frameworks = 'NetworkExtension', 'UserNotifications'
  s.libraries = 'resolv'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  }
end
