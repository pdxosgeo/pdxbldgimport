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

ways=DB.fetch %Q{
SELECT o.way_id,
  a.housenumber,
  a.street,
  a.postcode,
  a.city
FROM osm_buildings o
JOIN pdx_addrs a on (ST_Intersects(o.the_geom,a.the_geom))
where o.addr_street IS NULL
AND way_id IN (
  SELECT way_id
  FROM osm_buildings o
  JOIN pdx_addrs a on (ST_Intersects(o.the_geom,a.the_geom))
  GROUP BY way_id
  HAVING count(1)=1
)
ORDER BY postcode,street,housenumber;
}

# Rosemary::Api.base_uri 'http://api06.dev.openstreetmap.org/'
client = Rosemary::BasicAuthClient.new('USERNAME', 'PASSWORD')
api = Rosemary::Api.new(client)

changeset = api.create_changeset()

until ways.empty? do 
  count=0
  while count < 50 do 
    way=ways.pop
    x=api.find_way(way[:way_id])
    x.tags["addr:housenumber"]=way[:housenumber].to_s
    x.tags["addr:street"]=way[:street]
    x.tags["addr:postcode"]=way[:postcode]
    api.save(x, changeset)
    count+=1
  end
  api.close_changeset(changeset)
  sleep 60
  changeset = api.create_changeset()

end






