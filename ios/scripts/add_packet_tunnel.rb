#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the Packet Tunnel Network Extension target required by the sing_box
# plugin to a Flutter iOS project (idempotent: re-running updates it).
#
#   ruby "$(flutter pub cache path 2>/dev/null)/…/sing_box/ios/scripts/add_packet_tunnel.rb"
#   # or, inside your app:
#   ruby ios/.symlinks/plugins/sing_box/ios/scripts/add_packet_tunnel.rb --project ios/Runner.xcodeproj
#
# Options:
#   --project PATH     Xcode project (default: ios/Runner.xcodeproj or ./Runner.xcodeproj)
#   --target NAME      extension target name (default: PacketTunnel)
#   --bundle-id ID     extension bundle id (default: <app bundle id>.PacketTunnel)
#   --app-group ID     App Group shared by app and extension (default: group.<app bundle id>)
#   --team ID          DEVELOPMENT_TEAM (default: the Runner's team)
#
# What it does:
#   * creates <ios>/<target>/ with PacketTunnelProvider.swift
#     (`class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`), Info.plist,
#     entitlements and xcconfigs (which include Flutter's version numbers);
#   * adds the Network Extension + App Group entitlements to the Runner;
#   * adds the app extension target, embeds it into the Runner in an
#     "Embed Foundation Extensions" phase placed before Flutter's
#     "Thin Binary" script (avoids the "Cycle inside Runner" build error);
#   * adds the `SingBoxTunnel` pod for the extension to the Podfile (static
#     linkage, works whether the app uses Swift Package Manager or CocoaPods).
#
# Needs the `xcodeproj` gem, which ships with CocoaPods.

require 'fileutils'
require 'optparse'

def load_xcodeproj
  require 'xcodeproj'
rescue LoadError
  # Homebrew's CocoaPods keeps its gems in a private GEM_HOME.
  candidates = Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec') + Dir.glob('/usr/local/Cellar/cocoapods/*/libexec')
  home = candidates.max
  abort 'sing_box: the xcodeproj gem is required (gem install xcodeproj, or install CocoaPods)' unless home
  Dir.glob(File.join(home, 'gems', '*', 'lib')).each { |lib| $LOAD_PATH.unshift(lib) }
  require 'xcodeproj'
end
load_xcodeproj

options = { target: 'PacketTunnel' }
OptionParser.new do |o|
  o.on('--project PATH') { |v| options[:project] = v }
  o.on('--target NAME') { |v| options[:target] = v }
  o.on('--bundle-id ID') { |v| options[:bundle_id] = v }
  o.on('--app-group ID') { |v| options[:app_group] = v }
  o.on('--team ID') { |v| options[:team] = v }
end.parse!

project_path = options[:project] || %w[ios/Runner.xcodeproj Runner.xcodeproj].find { |p| File.directory?(p) }
abort 'sing_box: Runner.xcodeproj not found, pass --project' unless project_path && File.directory?(project_path)
ios_dir = File.dirname(File.expand_path(project_path))
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'sing_box: no Runner target'
name = options[:target]

runner_settings = runner.build_configurations.first.build_settings
app_bundle_id = runner_settings['PRODUCT_BUNDLE_IDENTIFIER'] or abort 'sing_box: Runner has no PRODUCT_BUNDLE_IDENTIFIER'
bundle_id = options[:bundle_id] || "#{app_bundle_id}.#{name}"
app_group = options[:app_group] || "group.#{app_bundle_id}"
team = options[:team] || runner_settings['DEVELOPMENT_TEAM']

# --- Files -------------------------------------------------------------------

ext_dir = File.join(ios_dir, name)
FileUtils.mkdir_p(ext_dir)

def write_unless_exists(path, content)
  return if File.exist?(path)

  File.write(path, content)
  puts "created #{path}"
end

write_unless_exists(File.join(ext_dir, 'PacketTunnelProvider.swift'), <<~SWIFT)
  import SingBoxTunnel

  /// The sing-box Packet Tunnel provider. All logic lives in the plugin's
  /// `SingBoxTunnel` library; override its methods only if you need to.
  class PacketTunnelProvider: SingBoxPacketTunnelProvider {}
SWIFT

write_unless_exists(File.join(ext_dir, 'Info.plist'), <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
  	<key>CFBundleDevelopmentRegion</key>
  	<string>$(DEVELOPMENT_LANGUAGE)</string>
  	<key>CFBundleDisplayName</key>
  	<string>#{name}</string>
  	<key>CFBundleExecutable</key>
  	<string>$(EXECUTABLE_NAME)</string>
  	<key>CFBundleIdentifier</key>
  	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  	<key>CFBundleInfoDictionaryVersion</key>
  	<string>6.0</string>
  	<key>CFBundleName</key>
  	<string>$(PRODUCT_NAME)</string>
  	<key>CFBundlePackageType</key>
  	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
  	<key>CFBundleShortVersionString</key>
  	<string>$(FLUTTER_BUILD_NAME)</string>
  	<key>CFBundleVersion</key>
  	<string>$(FLUTTER_BUILD_NUMBER)</string>
  	<key>NSExtension</key>
  	<dict>
  		<key>NSExtensionPointIdentifier</key>
  		<string>com.apple.networkextension.packet-tunnel</string>
  		<key>NSExtensionPrincipalClass</key>
  		<string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
  	</dict>
  	<key>SingBoxAppGroup</key>
  	<string>$(SING_BOX_APP_GROUP)</string>
  </dict>
  </plist>
PLIST

def entitlements(app_group)
  {
    'com.apple.developer.networking.networkextension' => ['packet-tunnel-provider'],
    'com.apple.security.application-groups' => [app_group],
  }
end

def merge_entitlements(path, app_group)
  existing = File.exist?(path) ? Xcodeproj::Plist.read_from_path(path) : {}
  entitlements(app_group).each do |key, values|
    existing[key] = ((existing[key] || []) + values).uniq
  end
  Xcodeproj::Plist.write_to_path(existing, path)
end

merge_entitlements(File.join(ext_dir, "#{name}.entitlements"), app_group)

configs = project.build_configurations.map(&:name)
configs.each do |config|
  pods = "Pods-#{name}.#{config.downcase}.xcconfig"
  File.write(File.join(ext_dir, "#{config}.xcconfig"), <<~XCCONFIG)
    // Generated by sing_box/ios/scripts/add_packet_tunnel.rb.
    #include? "../Pods/Target Support Files/Pods-#{name}/#{pods}"
    // FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER keep the extension version in sync with the app.
    #include "../Flutter/Generated.xcconfig"
    SING_BOX_APP_GROUP = #{app_group}
  XCCONFIG
end

# --- Runner entitlements ---------------------------------------------------

runner.build_configurations.each do |config|
  path = config.build_settings['CODE_SIGN_ENTITLEMENTS']
  unless path
    path = 'Runner/Runner.entitlements'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = path
  end
  merge_entitlements(File.join(ios_dir, path), app_group)
end
runner_group = project.main_group.find_subpath('Runner', false)
if runner_group && runner_group.files.none? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

# --- Extension target --------------------------------------------------------

target = project.targets.find { |t| t.name == name }
unless target
  target = project.new_target(:app_extension, name, :ios, '15.0', nil, :swift)
  puts "added target #{name}"
end

group = project.main_group.find_subpath(name, true)
group.set_source_tree('<group>')
group.set_path(name)
%w[PacketTunnelProvider.swift Info.plist].each do |file|
  group.files.find { |f| f.path == file } || group.new_reference(file)
end
group.files.find { |f| f.path == "#{name}.entitlements" } || group.new_reference("#{name}.entitlements")
configs.each { |c| group.files.find { |f| f.path == "#{c}.xcconfig" } || group.new_reference("#{c}.xcconfig") }

source = group.files.find { |f| f.path == 'PacketTunnelProvider.swift' }
target.source_build_phase.add_file_reference(source, true)
network_extension = project.frameworks_group.files.find { |f| f.path&.end_with?('NetworkExtension.framework') } ||
                    project.frameworks_group.new_file('System/Library/Frameworks/NetworkExtension.framework', :sdk_root)
target.frameworks_build_phase.add_file_reference(network_extension, true)

# One configuration per project configuration (Flutter uses Debug/Profile/Release).
configs.each do |config_name|
  config = target.build_configurations.find { |c| c.name == config_name }
  unless config
    template = target.build_configurations.find { |c| c.name == 'Release' }
    config = target.add_build_configuration(config_name, :release)
    config.build_settings.merge!(template.build_settings) if template
  end
  xcconfig = group.files.find { |f| f.path == "#{config_name}.xcconfig" }
  config.base_configuration_reference = xcconfig
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{name}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{name}/#{name}.entitlements"
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = team if team
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['ENABLE_BITCODE'] = 'NO'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# --- Embed into the Runner ---------------------------------------------------

runner.add_dependency(target) unless runner.dependencies.any? { |d| d.target == target }
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(target.product_reference)
  build_file = embed.add_file_reference(target.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
# Must run before Flutter's "Thin Binary" script, otherwise Xcode reports a
# dependency cycle inside Runner.
phases = runner.build_phases
phases.delete(embed)
thin = phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
phases.insert(thin || phases.length, embed)

project.save
puts "updated #{project_path} (#{name}: #{bundle_id}, App Group #{app_group})"

# --- Podfile -----------------------------------------------------------------

podfile = File.join(ios_dir, 'Podfile')
if File.exist?(podfile)
  content = File.read(podfile)
  unless content.include?("target '#{name}'")
    block = <<~RUBY

      # sing_box Packet Tunnel extension. Static linkage: works whether the app
      # links the plugin through Swift Package Manager or CocoaPods.
      target '#{name}' do
        use_frameworks! :linkage => :static
        pod 'SingBoxTunnel', :path => '.symlinks/plugins/sing_box/ios'
      end
    RUBY
    content = content.include?('post_install do') ? content.sub(/\npost_install do/, "#{block}\npost_install do") : content + block
    File.write(podfile, content)
    puts "added the #{name} target to #{podfile}"
  end
else
  warn "sing_box: no Podfile in #{ios_dir}; link the SingBoxTunnel library to #{name} yourself"
end

puts <<~TEXT
  Next steps:
    1. Enable the Network Extension and App Group (#{app_group}) capabilities for both
       #{app_bundle_id} and #{bundle_id} in your Apple Developer account.
    2. Run `flutter build ios` (it runs `pod install`).
    3. Initialize the plugin with the same ids if you changed the defaults:
       SingBoxIosOptions(appGroup: '#{app_group}', tunnelBundleIdentifier: '#{bundle_id}')
TEXT
