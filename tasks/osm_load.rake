# # Vancouver Extent
# n=46.0
# e=-122.2
# s=45.5
# w=-122.8
# 
# # Portland Extent
# n=45.8
# e=-121.7
# s=44.8
# w=-123.3

# Actual Extent
n=46.0
e=-121.7
s=44.8
w=-123.3


file 'osm/washington-latest.osm.pbf' do |t|
	sh %Q{wget -O #{t.name} --timestamping http://download.geofabrik.de/north-america/us/washington-latest.osm.pbf}
end
file 'osm/oregon-latest.osm.pbf' do |t|
	sh %Q{wget -O #{t.name} --timestamping http://download.geofabrik.de/north-america/us/oregon-latest.osm.pbf}
end
# file 'osm/clark_bldgs.osm' => 'osm/washington-latest.osm.pbf' do |t|
#  # %Q{ osmosis --read-pbf osm/oregon-latest.osm.pbf --truncate-pgsql database=pdx_bldgs --wp database=pdx_bldgs --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e}}
#  sh %Q{ osmosis --read-pbf osm/washington-latest.osm.pbf --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e} --write-xml file=#{t.name}}
# end
# file 'osm/pdx_bldgs.osm' => 'osm/oregon-latest.osm.pbf' do |t|
# 	 # %Q{ osmosis --read-pbf osm/oregon-latest.osm.pbf --truncate-pgsql database=pdx_bldgs --wp database=pdx_bldgs --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e}}
# 	 sh %Q{ osmosis --read-pbf osm/washington-latest.osm.pbf --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e} --write-xml file=#{t.name}}
# end

file 'osm/metro.osm.pbf' => ['osm/washington-latest.osm.pbf', 'osm/oregon-latest.osm.pbf'] do |t|
	sh %Q{ osmosis --read-pbf osm/washington-latest.osm.pbf --read-pbf osm/oregon-latest.osm.pbf --merge --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e}  --write-pbf file=#{t.name}  }
end

table :nodes => 'osm/metro.osm.pbf' do |t|
	sh %Q{osmosis --read-pbf 'osm/metro.osm.pbf' --bounding-box bottom=#{s} left=#{w} top=#{n} right=#{e} --truncate-pgsql database=pdx_bldgs --wp database=pdx_bldgs }
	t.add_update_column
end

table :ways => :nodes do |t|
	# loaded in nodes above, just add an updated_at column
	t.add_update_column
end
	
