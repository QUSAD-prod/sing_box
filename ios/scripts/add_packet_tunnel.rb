#!/usr/bin/env ruby
# frozen_string_literal: true

# Deprecated: kept for scripts written for sing_box 1.0.0. Use
#
#   dart run sing_box:setup_ios [--project ios/Runner.xcodeproj] [--target NAME]
#       [--bundle-id ID] [--app-group ID] [--team ID]
#
# in the app's root directory instead; it needs no Ruby gems and links the
# extension through Swift Package Manager or CocoaPods. This wrapper runs it
# with the same options.

project = nil
ARGV.each_with_index { |arg, i| project = ARGV[i + 1] if arg == '--project' }
start = File.expand_path(project ? File.dirname(project) : Dir.pwd)
root = start
root = File.dirname(root) until File.exist?(File.join(root, 'pubspec.yaml')) || root == '/'
abort 'sing_box: run this inside a Flutter app (no pubspec.yaml found)' if root == '/'

args = ARGV.dup
if project
  index = args.index('--project')
  args[index + 1] = File.expand_path(project)
end
Dir.chdir(root)
exec('dart', 'run', 'sing_box:setup_ios', *args)
