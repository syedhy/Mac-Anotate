require 'xcodeproj'
project_path = 'Anotate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group.find_subpath('Sources', true)
file_ref = group.new_file('SettingsWindowController.swift')
target.add_file_references([file_ref])
project.save
