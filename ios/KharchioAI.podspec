Pod::Spec.new do |s|
  s.name = 'KharchioAI'
  s.version = '1.0.0'
  s.summary = 'Local Whisper and Qwen inference for Kharchio'
  s.homepage = 'https://github.com/ggml-org/llama.cpp'
  s.license = { :type => 'MIT' }
  s.author = 'Kharchio'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/KharchioAI.xcframework'
  s.frameworks = 'Accelerate', 'Foundation', 'Metal', 'MetalKit'
  s.libraries = 'c++'
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_kharchio_transcribe -Wl,-u,_kharchio_extract -Wl,-u,_kharchio_free -Wl,-u,_kharchio_prepare_whisper -Wl,-u,_kharchio_prepare_qwen -Wl,-u,_kharchio_release_models -Wl,-u,_kharchio_set_processing -Wl,-u,_kharchio_last_backend'
  }
end
