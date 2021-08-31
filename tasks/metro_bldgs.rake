desc "Build our final table of buildings we want to add"
table :metro_bldgs => [:pdx_bldgs, :clark_bldgs_orig, :osm_buildings] do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} AS
		SELECT 
			prop_id::text as property_id
			,false::boolean is_deleted
			,addr_housenumber
			,addr_unit
			,addr_street
			,addr_city
			,coalesce(addr_state, 'WA') as addr_state
			,addr_postcode
			,addr_country
			,qtrsec
			,shape_area as area
			,no_addrs
			,NULLIF(numberstor,0) as levels
			,NULL::numeric as ele
			,NULL::numeric as height
			,'yes'::text as bldg_type
			,the_geom_centroids
			,st_multi(ST_SimplifyPreserveTopology(the_geom,0.000001))::geometry(MultiPolygon,4326) as the_geom
		FROM  clark_bldgs_orig
		
		UNION
		
		SELECT 
			state_id as property_id
			,false::boolean is_deleted
			,housenumber as addr_housenumber
			,''::text as addr_unit
			,street as addr_street
			,city as addr_city
			,coalesce(state, 'OR') as addr_state
			,postcode as addr_postcode
			,country as addr_country
			,qtrsec
			,area
			,no_addrs
			,levels
			,ele
			,height
			,bldg_type
			,the_geom_centroids
			,the_geom
		FROM pdx_bldgs;
	}
	
	t.run %Q{
		UPDATE #{t.name} a
		SET is_deleted=true
		FROM osm_buildings b
		where st_intersects(a.the_geom,b.the_geom);
	
		DROP TABLE IF EXISTS #{t.name}_deleted;
		CREATE TABLE #{t.name}_deleted AS
			SELECT * from #{t.name} 
			WHERE is_deleted=true;
		
		DELETE FROM #{t.name}
			WHERE is_deleted=true;
	}
	t.add_spatial_index :the_geom
	t.add_spatial_index :the_geom_centroids
	t.add_index :property_id
	t.add_update_column 
end
