require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ExpoAudioConverter'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = { :ios => '15.1' }
  s.swift_version  = '5.9'
  s.source         = { :git => 'https://github.com/avify-com/expo-opus.git', :tag => "v#{s.version}" }
  s.static_framework = true

  # Core Expo dependency
  s.dependency 'ExpoModulesCore'

  # LAME for MP3 encoding (pod version 1.2.x wraps LAME 3.100)
  s.dependency 'lame', '~> 1.2'

  # Vendored frameworks built from official Xiph.org sources
  # libopus 1.5.2 - https://downloads.xiph.org/releases/opus/
  # libogg 1.3.6 - https://downloads.xiph.org/releases/ogg/
  # Built with scripts/build-opus-ios.sh (SHA256 verified)
  s.vendored_frameworks = 'Frameworks/libopus.xcframework', 'Frameworks/libogg.xcframework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Shims/opus" "$(PODS_TARGET_SRCROOT)/Shims/ogg"',
    'SWIFT_INCLUDE_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Shims/opus" "$(PODS_TARGET_SRCROOT)/Shims/ogg"'
  }

  s.source_files = "**/*.{h,m,mm,swift}"
  s.exclude_files = ["Frameworks/**/*.h", "Shims/**/*"]
  s.preserve_paths = ['Frameworks/**/*', 'Shims/**/*']
end
