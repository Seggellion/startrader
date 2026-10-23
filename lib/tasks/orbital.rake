namespace :orbital do
  desc 'Read-only catalog identity audit without Rails initialization (DATABASE_URL or libpq variables)'
  task :validate do
    ruby File.expand_path('../../script/orbital_calibration.rb', __dir__)
  end
end
