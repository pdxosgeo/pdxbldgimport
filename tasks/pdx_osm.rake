desc "run all OSM-related tasks"
task :all_osm => [:osm_buildings,:osm_addrs]

# Actual Extent
n=45.8
e=-121.7
s=44.8
w=-123.3

# Test Extent
# n=45.57
# e=-122.68
# s=45.5
# w=-122.69
desc "Download buildings in OSM"
file 'osm/pdx_bldgs.osm'  do |t|
  sh %Q{
wget -O - 'http://overpass-api.de/api/interpreter?data=
<osm-script>
  <osm-script output="xml">
    <union>
      <query type="way">
         <has-kv k="building"/>
        <bbox-query e="#{e}" n="#{n}" s="#{s}" w="#{w}"/>
      </query>
      <query type="node">
                <bbox-query e="#{e}" n="#{n}" s="#{s}" w="#{w}"/>
      </query>
      <query type="relation">
        <has-kv k="building"/>
        <bbox-query e="#{e}" n="#{n}" s="#{s}" w="#{w}"/>
      </query>
    </union>
  <print mode="meta"/><!-- fixed by auto repair -->
    <recurse type="down"/>
  </osm-script>
' > #{t.name}
}
# load the OSM data. Unfortunately, osm2pgsql creates
# four tables out of each input file, so we
# need to make sure we get update columns on them all,
# but we only load the data once (in :portland_osm_line)

end

file 'osm/bldgs.osm' => [ 'osm/pdx_bldgs.osm','osm/clark_bldgs.osm',] do |t|
 sh %Q{ osmosis --rx osm/pdx_bldgs.osm --rx osm/clark_bldgs.osm --merge --wx #{t.name} }
 sh %Q{osmosis --read-xml osm/bldgs.osm --truncate-pgsql database=pdx_bldgs --wp database=pdx_bldgs }
 #sh %Q{osmosis --read-xml osm/rels.osm --write-pgsql database=pdx_bldgs --wp database=pdx_bldgs }

end



# desc "Create OSM ways table from raw osmosis data. Used by osm_buildings"
# task :portland_osm  => 'osm/bldgs.osm' do |t|
# end
