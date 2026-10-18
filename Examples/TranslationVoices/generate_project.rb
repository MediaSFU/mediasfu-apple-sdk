#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

root = Pathname(__dir__)
path = root + 'TranslationVoices.xcodeproj'
abort "Project already exists: #{path}; edit it in place or generate in a fresh copy." if path.exist?
project = Xcodeproj::Project.new(path)
target = project.new_target(:application, 'TranslationVoices', :ios, '15.0')
file = project.main_group.new_file('TranslationVoicesApp.swift')
target.add_file_references([file])
reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
reference.relative_path = '../..'
project.root_object.package_references << reference
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = reference
product.product_name = 'MediaSFUAppleSDK'
target.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
target.frameworks_build_phase.files << build_file
# The app constructs MSCDevice directly, so link its defining product explicitly.
native_reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
native_reference.relative_path = '../../../mediasfu-mediasoup-client-ios'
project.root_object.package_references << native_reference
native_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
native_product.package = native_reference
native_product.product_name = 'MediaSFUMediasoupClient'
target.package_product_dependencies << native_product
native_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
native_file.product_ref = native_product
target.frameworks_build_phase.files << native_file
embed = target.new_copy_files_build_phase('Embed Frameworks')
embed.dst_subfolder_spec = '10'
embedded = project.new(Xcodeproj::Project::Object::PBXBuildFile)
embedded.product_ref = product
embedded.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
embed.files << embedded
native_embedded = project.new(Xcodeproj::Project::Object::PBXBuildFile)
native_embedded.product_ref = native_product
native_embedded.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
embed.files << native_embedded
phase = target.new_shell_script_build_phase('Copy Compose resources')
phase.shell_script = <<~SCRIPT
  set -eu
  "${SRCROOT}/../../scripts/copy_compose_resources.sh" "${MEDIA_SFU_APPLE_ARTIFACTS_DIR:?Set MEDIA_SFU_APPLE_ARTIFACTS_DIR}" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
SCRIPT
phase.always_out_of_date = '1'
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.mediasfu.TranslationVoicesSample',
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_NSCameraUsageDescription' => 'Publish video to your test room.',
    'INFOPLIST_KEY_NSMicrophoneUsageDescription' => 'Publish speech for translation in your test room.',
    'INFOPLIST_FILE' => 'Info.plist',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks']
  })
end
tests = project.new_target(:ui_test_bundle, 'TranslationVoicesUITests', :ios, '15.0')
tests.add_dependency(target)
tests.add_file_references([project.main_group.new_file('TranslationVoicesUITests.swift')])
tests.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.mediasfu.TranslationVoicesSample.UITests',
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_TARGET_NAME' => 'TranslationVoices',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(tests)
scheme.set_launch_target(target)
scheme.save_as(path, 'TranslationVoices', true)
