require 'xcodeproj'

project_name = 'Anotate'
project = Xcodeproj::Project.new("#{project_name}.xcodeproj")

# Add a target for the Mac App
target = project.new_target(:application, project_name, :osx)

# Add source files
group = project.main_group.find_subpath('Sources', true)
group.set_source_tree('SOURCE_ROOT')
group.path = 'Sources'

Dir.glob('Sources/*.swift').each do |file|
    file_ref = group.new_reference(File.basename(file))
    target.add_file_references([file_ref])
end

# Build settings
target.build_configuration_list.build_configurations.each do |config|
    config.build_settings['INFOPLIST_FILE'] = 'Info.plist'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.Anotate'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

project.save
