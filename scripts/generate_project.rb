#!/usr/bin/env ruby
# Regenerate the standalone Mac project after adding source or test files.
# Uses the host's xcodeproj gem; runtime media must be hydrated with Git LFS.
require 'pathname'

root = File.expand_path('..', __dir__)
# Check before creating/replacing the project, even when xcodeproj is not installed.
unless system('/usr/bin/python3', '-B', File.join(__dir__, 'check_runtime_assets.py'), '--root', root)
  abort 'Runtime asset preflight failed; the Xcode project was not changed.'
end
require 'xcodeproj'

# The gem's default identity hashes children too, renumbering entire targets when a source is added.
class StableProjectUUIDGenerator < Xcodeproj::Project::UUIDGenerator
  private

  def path_component_for_object(object)
    reference = object.isa == 'PBXBuildFile' ? (object.file_ref || object.product_ref) : object
    [object.isa, reference.display_name,
     reference.respond_to?(:path) ? reference.path : nil,
     reference.respond_to?(:hierarchy_path) ? reference.hierarchy_path : nil].inspect
  end

  def verify_no_duplicates!(all_objects, all_new_objects)
    abort 'Ambiguous project object identities; the Xcode project was not changed.' unless all_objects.size == all_new_objects.size
  end
end

project_path = File.join(root, 'CatLifeMac.xcodeproj')
project = Xcodeproj::Project.new(project_path)
project.root_object.compatibility_version = 'Xcode 14.0'
project.root_object.development_region = 'zh_CN'
project.root_object.known_regions = ['zh_CN', 'en', 'Base']
project.add_build_configuration('AppStore', :release)
project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '6.0'
end
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = 'CatGameCore'
project.root_object.package_references << package

mac = project.new_target(:application, 'CatLifeMac', :osx, '14.0')
mac_group = project.main_group.new_group('CatLifeMac', 'CatLifeMac')
mac_shared = mac_group.new_group('Game sources', '../CatLife')
Dir.glob(File.join(root, 'CatLife', '**', '*.swift')).sort.each do |file|
  relative = Pathname.new(file).relative_path_from(Pathname.new(File.join(root, 'CatLife'))).to_s
  mac.source_build_phase.add_file_reference(mac_shared.new_file(relative))
end
Dir.glob(File.join(root, 'CatLifeMac', '**', '*.swift')).sort.each do |file|
  relative = Pathname.new(file).relative_path_from(Pathname.new(File.join(root, 'CatLifeMac'))).to_s
  mac.source_build_phase.add_file_reference(mac_group.new_file(relative))
end
mac.resources_build_phase.add_file_reference(mac_shared.new_file('Assets.xcassets'))
mac.resources_build_phase.add_file_reference(mac_shared.new_file('PrivacyInfo.xcprivacy'))
mac_group.new_file('CatLifeMac-AppStore.entitlements')
mac_audio = mac_shared.new_file('Audio'); mac_audio.last_known_file_type = 'folder'
mac.resources_build_phase.add_file_reference(mac_audio)
if File.directory?(File.join(root, 'CatLifeMac', 'Assets.xcassets'))
  mac.resources_build_phase.add_file_reference(mac_group.new_file('Assets.xcassets'))
end
mac_preflight = mac.new_shell_script_build_phase('Check Runtime Assets')
mac_preflight.shell_path = '/bin/sh'
mac_preflight.shell_script = '/usr/bin/python3 -B "$SRCROOT/scripts/check_runtime_assets.py" --root "$SRCROOT"'
mac_preflight.input_paths = ['$(SRCROOT)/scripts/check_runtime_assets.py', '$(SRCROOT)/scripts/runtime_assets.json', '$(SRCROOT)/scripts/runtime_assets.xcfilelist']
mac_preflight.input_file_list_paths = ['$(SRCROOT)/scripts/runtime_assets.xcfilelist']
mac_preflight.always_out_of_date = '1'; mac_preflight.show_env_vars_in_log = '0'
mac.build_phases.delete(mac_preflight); mac.build_phases.unshift(mac_preflight)
mac_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mac_dependency.package = package; mac_dependency.product_name = 'CatGameCore'
mac.package_product_dependencies << mac_dependency
mac_framework = project.new(Xcodeproj::Project::Object::PBXBuildFile)
mac_framework.product_ref = mac_dependency; mac.frameworks_build_phase.files << mac_framework
mac.build_configurations.each do |config|
  app_store = config.name == 'AppStore'
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.stationcat.catlife.mac', 'PRODUCT_NAME' => 'CatLifeMac',
    'INFOPLIST_FILE' => 'CatLifeMac/Info.plist', 'GENERATE_INFOPLIST_FILE' => 'NO',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0', 'SUPPORTED_PLATFORMS' => 'macosx',
    'SWIFT_VERSION' => '6.0', 'SWIFT_STRICT_CONCURRENCY' => 'complete',
    'CODE_SIGN_STYLE' => 'Automatic', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
    'ENABLE_HARDENED_RUNTIME' => 'YES', 'ENABLE_APP_SANDBOX' => app_store ? 'YES' : 'NO',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'MacAppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor', 'SWIFT_EMIT_LOC_STRINGS' => 'NO'
  })
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'CatLifeMac/CatLifeMac-AppStore.entitlements' if app_store
end
mac_tests = project.new_target(:unit_test_bundle, 'CatLifeMacTests', :osx, '14.0')
mac_tests.add_dependency(mac)
mac_test_group = project.main_group.new_group('CatLifeMacTests', 'CatLifeMacTests')
Dir.glob(File.join(root, 'CatLifeMacTests', '*.swift')).sort.each do |file|
  mac_tests.source_build_phase.add_file_reference(mac_test_group.new_file(File.basename(file)))
end
mac_test_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mac_test_dependency.package = package; mac_test_dependency.product_name = 'CatGameCore'
mac_tests.package_product_dependencies << mac_test_dependency
mac_test_framework = project.new(Xcodeproj::Project::Object::PBXBuildFile)
mac_test_framework.product_ref = mac_test_dependency; mac_tests.frameworks_build_phase.files << mac_test_framework
mac_tests.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.stationcat.catlife.mac.tests', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0', 'SUPPORTED_PLATFORMS' => 'macosx', 'SWIFT_VERSION' => '6.0',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/CatLifeMac.app/Contents/MacOS/CatLifeMac', 'BUNDLE_LOADER' => '$(TEST_HOST)',
    'CODE_SIGN_STYLE' => 'Automatic'
  })
end
mac_ui = project.new_target(:ui_test_bundle, 'CatLifeMacUITests', :osx, '14.0')
mac_ui.add_dependency(mac)
mac_ui_group = project.main_group.new_group('CatLifeMacUITests', 'CatLifeMacUITests')
Dir.glob(File.join(root, 'CatLifeMacUITests', '*.swift')).sort.each do |file|
  mac_ui.source_build_phase.add_file_reference(mac_ui_group.new_file(File.basename(file)))
end
mac_ui.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.stationcat.catlife.mac.uitests', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0', 'SUPPORTED_PLATFORMS' => 'macosx', 'SWIFT_VERSION' => '6.0',
    'TEST_TARGET_NAME' => 'CatLifeMac', 'CODE_SIGN_STYLE' => 'Automatic'
  })
end
StableProjectUUIDGenerator.new([project]).generate!
project.save
mac_scheme = Xcodeproj::XCScheme.new
mac_scheme.add_build_target(mac); mac_scheme.set_launch_target(mac)
mac_scheme.add_build_target(mac_tests); mac_scheme.add_test_target(mac_tests)
mac_scheme.add_build_target(mac_ui)
mac_scheme.add_test_target(mac_ui)
mac_scheme.build_action.entries.each do |entry|
  next if entry.buildable_references.first.target_uuid == mac.uuid
  entry.build_for_running = false; entry.build_for_profiling = false
  entry.build_for_archiving = false; entry.build_for_analyzing = false
end
mac_scheme.save_as(project_path, 'CatLifeMac', true)
store_scheme = Xcodeproj::XCScheme.new
store_scheme.add_build_target(mac); store_scheme.set_launch_target(mac)
store_scheme.test_action.build_configuration = 'AppStore'
store_scheme.launch_action.build_configuration = 'AppStore'
store_scheme.profile_action.build_configuration = 'AppStore'
store_scheme.analyze_action.build_configuration = 'AppStore'
store_scheme.archive_action.build_configuration = 'AppStore'
store_scheme.save_as(project_path, 'CatLifeMac-AppStore', true)
puts "Generated #{project_path}"
