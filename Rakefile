$:<<'./lib'
require "rubygems"
require "bundler/setup" 
require 'postgistable'


Dir.glob('tasks/*.rake').each { |r| import r }
Dir.glob('tasks/**/*.rake').each { |r| import r }

ENV['PGUSER']='darrell'
ENV['PGDATABASE']='pdx_bldgs'
ENV['PGHOST']='localhost'


Rake::TableTask::Config.dbname=ENV['PGDATABASE']
Rake::TableTask::Config.dbuser=ENV['PGUSER']
Rake::TableTask::Config.dbhost=ENV['PGHOST']

# we set DB for the census lib, which should probably be
# merged into postgistable someday.
DB=Sequel.connect Rake::TableTask::Config.sequel_connect_string

desc "Automatically execute any task beginning with 'all_'"
task :default do |t|
  Rake::Task.tasks.each do |task|
    task.invoke if task.name =~ /^all_/
  end
end


