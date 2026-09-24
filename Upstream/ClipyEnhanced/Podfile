platform :macos, '13.0'
use_frameworks!
inhibit_all_warnings!

target 'Clipy' do

  # Application
  pod 'PINCache'
  pod 'Sauce'
  pod 'RealmSwift'
  pod 'RxCocoa'
  pod 'RxSwift'
  pod 'LoginServiceKit', :git => 'https://github.com/Clipy/LoginServiceKit.git'
  pod 'KeyHolder'
  pod 'Magnet'
  pod 'AEXML'
  pod 'LetsMove'
  pod 'SwiftHEXColors'
  # Utility
  pod 'BartyCrouch'
  pod 'SwiftLint'
  pod 'SwiftGen'

  target 'ClipyTests' do
    inherit! :search_paths

    pod 'Quick'
    pod 'Nimble'

  end

end

post_install do |installer|
  require 'fileutils'

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    end
  end

  # Realm 10.7.2 predates the stricter header identity handling in newer Xcode.
  # Keep duplicate Realm/include headers as one physical file and make private
  # implementation includes local, avoiding duplicate Objective-C interfaces.
  realm_root = File.join(installer.sandbox.root.to_s, 'Realm')
  realm_headers = File.join(realm_root, 'Realm')
  realm_include = File.join(realm_root, 'include')
  Dir.glob(File.join(realm_include, '*.{h,hpp}')).each do |include_path|
    header_path = File.join(realm_headers, File.basename(include_path))
    next unless File.exist?(header_path)
    next if File.identical?(include_path, header_path)

    FileUtils.rm_f(header_path)
    begin
      File.link(include_path, header_path)
    rescue SystemCallError
      FileUtils.ln_sf(include_path, header_path)
    end
  end

  Dir.glob(File.join(realm_headers, '*_Private.hpp')).each do |path|
    source = File.read(path)
    patched = source.gsub(/#import <Realm\/([^>]+)>/, '#import "\\1"')
    File.write(path, patched) if patched != source
  end
end
