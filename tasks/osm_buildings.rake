
desc "Convert OSM ways into a buildings layer with appropriate tags"
table :osm_buildings => [:ways] do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} as
		SELECT 
		id as way_id,
		tags -> 'access' as access,
		tags -> 'addr:housename' as addr_housename,
		tags -> 'addr:housenumber' as addr_housenumber,
		tags -> 'addr:interpolation' as addr_interpolation,
		tags -> 'addr:street' as addr_street,
		tags -> 'addr:postcode' as addr_postcode,
		tags -> 'addr:city' as addr_city,
		tags -> 'addr:unit' as addr_unit,
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
		FROM ways
		WHERE st_isclosed(linestring) AND (tags -> 'building' <> '' OR tags -> 'destroyed:building' <> '');
	}

	# now get the multipolygons
	t.run %Q{
	INSERT INTO #{t.name}
	WITH inside as (
		SELECT 
			rm.relation_id,
			rm.member_role,
			array_agg(ST_LineMerge(w.linestring)) as the_geom
			FROM  relation_members rm 
			JOIN ways w on (w.id=rm.member_id)
			WHERE rm.member_type='W'
			AND rm.member_role='inner'
			AND st_isclosed(w.linestring)
			 -- AND rm.relation_id=5262654
			GROUP BY rm.relation_id, rm.member_role
		)
		, outside as (
			SELECT 
			rm.relation_id,
			rm.member_role,
			ST_LineMerge(w.linestring) as the_geom
			FROM  relation_members rm 
			JOIN ways w on (w.id=rm.member_id)
			WHERE rm.member_type='W'
			AND rm.member_role='outer'
			AND st_isclosed(w.linestring)
			--AND rm.relation_id=5262654
			GROUP BY rm.relation_id, rm.member_role,w.linestring
		)
		SELECT 
			outside.relation_id as way_id,
			tags -> 'access' as access,
			tags -> 'addr:housename' as addr_housename,
			tags -> 'addr:housenumber' as addr_housenumber,
			tags -> 'addr:interpolation' as addr_interpolation,
			tags -> 'addr:street' as addr_street,
			tags -> 'addr:postcode' as addr_postcode,
			tags -> 'addr:city' as addr_city,
			tags -> 'addr:unit' as addr_unit,
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
			st_setsrid(st_makepolygon(outside.the_geom,inside.the_geom),4326) as the_geom
			from outside
			join inside on outside.relation_id=inside.relation_id
			JOIN relations r on outside.relation_id=r.id
			WHERE  (tags -> 'building' <> '' OR tags -> 'destroyed:building' <> '');
}
	t.add_spatial_index
	t.add_update_column
end

desc "Convert nodes into address points"
table :osm_addrs => 'osm/metro.osm.pbf' do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} AS 
		SELECT 
		id as node_id,
		tags -> 'addr:housename' as addr_housename,
		tags -> 'addr:housenumber' as addr_housenumber,
		tags -> 'addr:interpolation' as addr_interpolation,
		tags -> 'addr:street' as addr_street,
		tags -> 'addr:unit' as addr_unit,
		tags -> 'addr:postcode' as addr_postcode,
		tags -> 'addr:city' as addr_city,
		tags -> 'addr:country' as addr_country,
		tags -> 'addr:full' as addr_full,
		tags -> 'addr:state' as addr_state,
		geom as the_geom
		FROM nodes
		WHERE tags -> 'addr:street' <>'';
	}
	t.add_spatial_index
	t.add_update_column

 end