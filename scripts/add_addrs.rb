#!env ruby
$:<<'./lib'
require "rubygems"
require "bundler/setup" 
require 'postgistable'
require 'pry'
require 'rosemary'

ENV['PGUSER']='darrell'
ENV['PGDATABASE']='pdx_bldgs'
ENV['PGHOST']='localhost'

Rake::TableTask::Config.dbname=ENV['PGDATABASE']
Rake::TableTask::Config.dbuser=ENV['PGUSER']
Rake::TableTask::Config.dbhost=ENV['PGHOST']

# we set DB for the census lib, which should probably be
# merged into postgistable someday.
DB=Sequel.connect Rake::TableTask::Config.sequel_connect_string

# Rosemary::Api.base_uri 'http://api06.dev.openstreetmap.org/'
client = Rosemary::BasicAuthClient.new('Darrell_pdxbuildings', '4cdcU2qgYKiATjU')
api = Rosemary::Api.new(client)


[97209,
  97210,97211,97212,97213,97214,97215,97216,97217,97218,97219,97220,
  97221,97222,97223,97224,97225,97227,97230,97232,97236,97239,
  97266,97267].each do |zip|

  ways=DB.fetch %Q{
  select *
  from osm_addrs_to_add
  where postcode='#{zip}'
  order by street,housenumber
  }

  begin
  changeset = api.create_changeset("Add missing addresses to ~#{ways.count} buildings in #{zip}")

  puts "Starting zip #{zip} with #{ways.count} addresses to add"
  ways.each do |way|
    # puts way
    x=api.find_way(way[:way_id])
    next if x.tags["building"].nil?
    x.tags["addr:housenumber"]||=way[:housenumber].to_s
    x.tags["addr:street"]||=way[:street]
    x.tags["addr:city"]||=way[:city]
    x.tags["addr:postcode"]||=way[:postcode]
    api.save(x, changeset)
    puts "    " + way[:way_id].to_s + ':  ' + x.tags.to_s
  end
  api.close_changeset(changeset)
  puts "Closing changeset"
  puts "=========================="
  puts ""
  sleep 15
rescue
    puts "caught error, exiting"
    api.close_changeset(changeset)
    exit(1)
  end
end






