require "bridgetown"

Bridgetown.load_tasks

# Run rake without specifying any command to execute a deploy build by default.
task default: :deploy

#
# Standard set of tasks, which you can customize if you wish:
#
desc "Build the Bridgetown site for deployment"
task :deploy => [:clean, "frontend:build"] do
  Bridgetown::Commands::Build.start
end

desc "Build the site in a test environment"
task :test do
  ENV["BRIDGETOWN_ENV"] = "test"
  Bridgetown::Commands::Build.start
end

desc "Runs the clean command"
task :clean do
  Bridgetown::Commands::Clean.start
end

namespace :frontend do
  desc "Build the frontend with esbuild for deployment"
  task :build do
    sh "npm run esbuild"
  end

  desc "Watch the frontend with esbuild during development"
  task :dev do
    sh "npm run esbuild-dev"
  rescue Interrupt
  end
end

require 'rake/testtask'

# Plugin testing tasks (separate from existing :test task)
namespace :spec do
  desc "Run ObsidianMediaBlocks tests"
  Rake::TestTask.new(:obsidian_media_blocks) do |t|
    t.libs << 'test'
    t.libs << 'plugins' # Assuming your plugin is in plugins/ directory
    t.test_files = FileList['test/**/obsidian_media_blocks_test.rb']
    t.verbose = true
  end

  desc "Run all plugin tests"
  Rake::TestTask.new(:plugins) do |t|
    t.libs << 'test'
    t.libs << 'plugins'
    t.test_files = FileList['test/**/*_test.rb']
    t.verbose = true
  end

  desc "Run tests with coverage report"
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task['spec:plugins'].invoke
  end

  desc "Run plugin tests after building test environment"
  task :all => [:test] do  # Depends on your existing :test task
    Rake::Task['spec:plugins'].invoke
  end
end

# Individual test file runner
desc "Run a specific test file"
task :test_file, [:file] do |t, args|
  if args[:file]
    ruby "test/#{args[:file]}_test.rb"
  else
    puts "Usage: rake test_file[obsidian_media_blocks]"
  end
end


#
# Add your own Rake tasks here! You can use `environment` as a prerequisite
# in order to write automations or other commands requiring a loaded site.
#
# task :my_task => :environment do
#   puts site.root_dir
#   automation do
#     say_status :rake, "I'm a Rake tast =) #{site.config.url}"
#   end
# end
