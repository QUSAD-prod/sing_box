# Resolves Libbox.xcframework (the sing-box core) for the CocoaPods specs.
#
# The core is `standard` unless the environment variable `SING_BOX_CORE` or
# `sing_box: core:` in the app's pubspec.yaml (next to the directory of the
# app's Podfile) says `lx`; the sing-box-lx core uses `libboxLx*` of
# Package.swift and `sing_box/Frameworks/lx/`.
#
# The ~200 MB framework is not part of the pub package. The version, checksum
# and download URL are read from `sing_box/Package.swift` (the single source of
# truth shared with Swift Package Manager). Lookup order:
#
#   1. `sing_box/Frameworks/Libbox.xcframework` (local build, git-ignored;
#      lx: `sing_box/Frameworks/lx/Libbox.xcframework`);
#   2. the environment variable `SING_BOX_LIBBOX_XCFRAMEWORK_ZIP` - a local
#      `Libbox.xcframework.zip` (offline builds);
#   3. a download of `<base>/libbox-v<version>/Libbox.xcframework.zip` into
#      `~/Library/Caches/sing_box/libbox/<version>/`, verified with SHA-256.
#      `SING_BOX_LIBBOX_BASE_URL` overrides the base URL (mirrors).
#
# The archive is unpacked into `sing_box/Frameworks/` so that both pods
# (`sing_box` and `SingBoxTunnel`) vendor the same framework.
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

module SingBoxLibbox
  module_function

  # `lx` or `standard`, see the top of this file.
  def core
    @core ||= begin
      name = ENV['SING_BOX_CORE'].to_s.strip
      name = pubspec_core(File.join(app_ios_dir, '..', 'pubspec.yaml')).to_s if name.empty?
      name = 'standard' if name.empty?
      raise "sing_box: unknown core `#{name}` (standard or lx)" unless %w[standard lx].include?(name)

      name
    end
  end

  def lx?
    core == 'lx'
  end

  # The app's `ios/` directory: where its Podfile is. CocoaPods evaluates a
  # podspec inside the podspec's own directory, so Dir.pwd is the plugin.
  def app_ios_dir
    if defined?(Pod::Config) && Pod::Config.instance.installation_root
      Pod::Config.instance.installation_root.to_s
    else
      Dir.pwd
    end
  end

  # `core` of the top-level `sing_box:` map in [pubspec] (block or flow style).
  def pubspec_core(pubspec)
    return nil unless File.file?(pubspec)

    text = File.read(pubspec)
    flow = text.match(/^sing_box:\s*\{[^}]*\bcore:\s*['"]?([\w-]+)/)
    return flow[1] if flow

    in_block = false
    text.each_line do |line|
      content = line.sub(/#.*/, '').rstrip
      next if content.empty?

      unless line.start_with?(' ', "\t")
        in_block = content == 'sing_box:'
        next
      end
      match = content.match(/^\s+core:\s*['"]?([\w-]+)/)
      return match[1] if in_block && match
    end
    nil
  end

  # Path of the framework relative to the podspec directory.
  def framework
    lx? ? 'sing_box/Frameworks/lx/Libbox.xcframework' : 'sing_box/Frameworks/Libbox.xcframework'
  end

  # Sources of the plugin pod for the other core (see Package.swift).
  def other_core_sources
    lx? ? 'sing_box/Sources/sing_box/Core/standard/**/*' : 'sing_box/Sources/sing_box/Core/lx/**/*'
  end

  # Makes sure the framework exists next to the podspec in [dir] and returns
  # its path relative to [dir] (for `vendored_frameworks`).
  def ensure!(dir)
    target = File.join(dir, framework)
    return framework if File.exist?(File.join(target, 'Info.plist'))

    manifest = File.read(File.join(dir, 'sing_box', 'Package.swift'))
    version = value(manifest, lx? ? 'libboxLxVersion' : 'libboxVersion')
    checksum = value(manifest, lx? ? 'libboxLxChecksum' : 'libboxChecksum').downcase
    base = (ENV['SING_BOX_LIBBOX_BASE_URL'] || value(manifest, 'libboxBaseURL')).chomp('/')

    zip = ENV['SING_BOX_LIBBOX_XCFRAMEWORK_ZIP']
    if zip.nil? || zip.empty?
      zip = cached_download("#{base}/libbox-v#{version}/Libbox.xcframework.zip", version, checksum)
    else
      raise "sing_box: #{zip} does not exist (SING_BOX_LIBBOX_XCFRAMEWORK_ZIP)" unless File.file?(zip)

      actual = Digest::SHA256.file(zip).hexdigest
      unless actual == checksum
        Pod::UI.warn("sing_box: #{zip} sha256 #{actual} differs from Package.swift (#{checksum}); using it anyway") if defined?(Pod::UI)
      end
    end
    unpack(zip, File.dirname(target))
    raise "sing_box: #{zip} does not contain Libbox.xcframework" unless File.exist?(File.join(target, 'Info.plist'))

    framework
  end

  def value(manifest, name)
    match = manifest.match(/let\s+#{name}\s*=\s*"([^"]*)"/)
    raise "sing_box: `let #{name} = \"...\"` not found in Package.swift" unless match

    match[1]
  end

  def cached_download(url, version, checksum)
    cache = File.join(Dir.home, 'Library', 'Caches', 'sing_box', 'libbox', version)
    zip = File.join(cache, 'Libbox.xcframework.zip')
    return zip if File.file?(zip) && Digest::SHA256.file(zip).hexdigest == checksum

    FileUtils.mkdir_p(cache)
    part = "#{zip}.#{Process.pid}.part"
    log("sing_box: downloading libbox #{version} from #{url}")
    _, error, status = Open3.capture3('curl', '-fL', '--retry', '3', '--connect-timeout', '30', '-o', part, url)
    unless status.success?
      FileUtils.rm_f(part)
      raise "sing_box: failed to download libbox #{version} from #{url}: #{error.strip}\n" \
            'Offline or blocked? Download Libbox.xcframework.zip manually and set ' \
            'SING_BOX_LIBBOX_XCFRAMEWORK_ZIP to its path, or set SING_BOX_LIBBOX_BASE_URL to a mirror.'
    end
    actual = Digest::SHA256.file(part).hexdigest
    unless actual == checksum
      FileUtils.rm_f(part)
      raise "sing_box: sha256 mismatch for #{url}\n  expected: #{checksum}\n  actual:   #{actual}"
    end
    File.rename(part, zip)
    zip
  end

  def unpack(zip, destination)
    FileUtils.mkdir_p(destination)
    Dir.mktmpdir('sing_box_libbox') do |tmp|
      _, error, status = Open3.capture3('ditto', '-x', '-k', zip, tmp)
      raise "sing_box: cannot unpack #{zip}: #{error.strip}" unless status.success?

      source = Dir.glob(File.join(tmp, '**', 'Libbox.xcframework')).first
      raise "sing_box: #{zip} does not contain Libbox.xcframework" unless source

      target = File.join(destination, 'Libbox.xcframework')
      FileUtils.rm_rf(target)
      FileUtils.mv(source, target)
    end
  end

  def log(message)
    defined?(Pod::UI) ? Pod::UI.puts(message) : puts(message)
  end
end
