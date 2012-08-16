Pod::Spec.new do |s|
  s.name         = 'DSTStorageEngine'
  s.version      = '0.1'
  s.license      = 'BSD'
  s.homepage     = 'https://github.com/dunkelstern/DSTStorageEngine'
  s.authors      = { 'Johannes Schriewer' => 'jschriewer@gmail.com' }
  s.summary      = 'Simple Objective-C persistence layer based on SQLite 3 backend.'
  s.source       = { :git => 'https://github.com/dunkelstern/DSTStorageEngine.git', :tag => '0.1' }
  s.source_files = 'StorageEngine/*'
  s.requires_arc = true
  s.library      = 'sqlite3'
end
