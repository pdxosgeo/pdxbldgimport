table :osm_construction_sites => [:ways]  do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} as
		SELECT 
		id as way_id,
		tags,
		st_multi(st_setsrid(st_makepolygon(linestring),4326))::geometry(MultiPolygon,4326) as the_geom
		FROM ways
		WHERE st_isclosed(linestring) AND
		(tags -> 'landuse' = 'construction');
	}
	t.add_update_column
	t.add_spatial_index :the_geom
end