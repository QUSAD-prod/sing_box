#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sing_box.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'sing_box'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for sing-box, providing platform-specific implementations for Android and iOS.'
  s.description      = <<-DESC
A Flutter plugin for sing-box, providing platform-specific implementations for Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/qusadprod/sing_box'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'qusadprod' => 'https://github.com/qusadprod' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  
  # Libbox framework
  s.vendored_frameworks = 'Frameworks/Libbox.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'sing_box_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
