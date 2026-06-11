#!/usr/bin/env ruby
# Adds the BroadcastExtension target to the Xcode project.
# Usage: cd ios && ruby setup_broadcast_extension.rb

require 'xcodeproj'

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Skip if target already exists
if project.targets.any? { |t| t.name == 'BroadcastExtension' }
  puts "BroadcastExtension target already exists, skipping."
  exit 0
end

# ─── Create Extension Target ──────────────────────────────────────────
ext_target = project.new_target(
  :app_extension,
  'BroadcastExtension',
  :ios,
  '15.0'
)

# ─── Add source files ─────────────────────────────────────────────────
ext_group = project.main_group.new_group('BroadcastExtension', 'BroadcastExtension')
shared_group = project.main_group.new_group('Shared', 'Shared')

ext_group.new_file('SampleHandler.swift')
ext_group.new_file('Info.plist')
ext_group.new_file('BroadcastExtension.entitlements')
shared_ref = shared_group.new_file('FrameShared.swift')

# Add files to target's compile sources
ext_target.add_file_references(
  [ext_group.files.find { |f| f.path == 'SampleHandler.swift' }, shared_ref].compact
)

# ─── Build settings ───────────────────────────────────────────────────
ext_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.qsw.rdesk.BroadcastExtension'
  config.build_settings['INFOPLIST_FILE'] = 'BroadcastExtension/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'BroadcastExtension/BroadcastExtension.entitlements'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = '' # Will be set manually
end

# ─── Add FrameShared.swift to Runner target too ────────────────────────
runner_target = project.targets.find { |t| t.name == 'Runner' }
if runner_target
  runner_target.add_file_references([shared_ref].compact)

  # Add entitlements to Runner
  runner_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  end
end

# ─── Embed extension in Runner ─────────────────────────────────────────
# Add "Embed App Extensions" build phase
embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13' # app extensions
embed_phase.add_file_reference(ext_target.product_reference)

# Move embed phase right after Resources to avoid build cycle with Pod scripts
runner_target.build_phases.delete(embed_phase)
resources_idx = runner_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
runner_target.build_phases.insert((resources_idx || 0) + 1, embed_phase)

# Add target dependency
runner_target.add_dependency(ext_target)

# ─── Add ReplayKit framework ──────────────────────────────────────────
ext_target.add_system_framework('ReplayKit')

# ─── Save ──────────────────────────────────────────────────────────────
project.save
puts "BroadcastExtension target added successfully!"
puts ""
puts "NEXT STEPS:"
puts "1. Open Runner.xcworkspace in Xcode"
puts "2. Select BroadcastExtension target → Signing & Capabilities"
puts "3. Set your Development Team"
puts "4. Add 'App Groups' capability with 'group.com.qsw.rdesk'"
puts "5. Select Runner target → Signing & Capabilities"
puts "6. Add 'App Groups' capability with 'group.com.qsw.rdesk'"
puts "7. Build and run on device"
