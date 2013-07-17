file 'osm/bldgs.osm.bz2' do |t|
  sh %Q{
wget -O - 'http://overpass-api.de/api/interpreter?data=
<osm-script>
  <osm-script output="xml">
    <union>
      <query type="way">
         <has-kv k="building"/>
        <bbox-query e="-121.926452653623" n="45.7254175022529" s="45.2012894970606" w="-123.19651445735"/>
      </query>
      <query type="node">
        <bbox-query e="-121.926452653623" n="45.7254175022529" s="45.2012894970606" w="-123.19651445735"/>
      </query>
      <query type="relation">
        <bbox-query e="-121.926452653623" n="45.7254175022529" s="45.2012894970606" w="-123.19651445735"/>
      </query>
    </union>
  <print mode="meta"/><!-- fixed by auto repair -->
    <recurse type="down"/>
  </osm-script>
</osm-script>
' | bzip2 -c > #{t.name}
}
end


# load the OSM data. Unfortunately, osm2pgsql creates
# four tables out of each input file, so we
# need to make sure we get update columns on them all,
# but we only load the data once (in :portland_osm_line)

task :portland_osm  do |t|
 sh %Q{osmosis --read-xml osm/bldgs.osm --truncate-pgsql database=pdx_bldgs --wp database=pdx_bldgs }
end

table :pdx_bldgs do |t|
  t.drop_table
  t.run %Q{
  create table #{t.name} as
  select 
  tags -> 'access' as access,
  tags -> 'addr:housename' as addr_housename,
  tags -> 'addr:housenumber' as addr_housenumber,
  tags -> 'addr:interpolation' as addr_interpolation,
  tags -> 'addr:street' as addr_street,
  tags -> 'addr:postcode' as addr_postcode,
  tags -> 'addr:city' as addr_city,
  tags -> 'addr:country' as addr_country,
  tags -> 'addr:full' as addr_full,
  tags -> 'addr:state' as addr_state,
  tags -> 'area' as area,
  tags -> 'building' as building,
  tags -> 'building:levels' as building_levels,
  tags -> 'construction' as construction,
  tags -> 'generator:source' as generator_source,
  tags -> 'man_made' as man_made,
  tags -> 'motorcar' as motorcar,
  tags -> 'name' as name,
  tags -> 'office' as office,
  tags -> 'place' as place,
  tags -> 'ref' as ref,
  tags -> 'religion' as religion,
  tags -> 'shop' as shop,
  st_setsrid(st_makepolygon(linestring),4326) as the_geom
  from ways
  where st_isclosed(linestring) and tags -> 'building' <> '';
}
  t.add_spatial_index
  t.add_update_column
end
