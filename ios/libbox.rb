# Resolves Libbox.xcframework (the sing-box core) for the CocoaPods specs.
#
# The ~200 MB framework is not part of the pub package. The version, checksum
# and download URL are read from `sing_box/Package.swift` (the single source of
# truth shared with Swift Package Manager). Lookup order:
#
#   1. `sing_box/Frameworks/Libbox.xcframework` (local build, git-ignored);
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
  FRAMEWORK = 'sing_box/Frameworks/Libbox.xcframework'.freeze

  module_function

  # Makes sure the framework exists next to the podspec in [dir] and returns
  # its path relative to [dir] (for `vendored_frameworks`).
  def ensure!(dir)
    target = File.join(dir, FRAMEWORK)
    return FRAMEWORK if File.exist?(File.join(target, 'Info.plist'))

    manifest = File.read(File.join(dir, 'sing_box', 'Package.swift'))
    version = value(manifest, 'libboxVersion')
    checksum = value(manifest, 'libboxChecksum').downcase
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

    FRAMEWORK
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
