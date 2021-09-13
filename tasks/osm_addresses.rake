table :osm_addresses => [:ways, :nodes] do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} AS
		SELECT id as way_id,
			NULL::integer as node_id,
			'way'::text as type,
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
			tags -> 'demolished:building' as demolished_building,
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
			WHERE st_isclosed(linestring) AND tags -> 'addr:street' <> '' AND tags -> 'addr:housenumber' <> ''
			UNION ALL
			SELECT NULL as way_id,
			id as node_id,
			'node'::text as type,
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
			tags -> 'demolished:building' as demolished_building,
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
			geom as the_geom
			FROM nodes
			WHERE tags -> 'addr:street' <> '' AND tags -> 'addr:housenumber' <> '';
			}
end
	