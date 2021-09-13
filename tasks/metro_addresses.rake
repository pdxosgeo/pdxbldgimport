desc "Build our final table of addresses we want to add"
table :metro_addresses => [:clark_addrs_orig, :osm_addresses] do |t|
	t.drop_table
	t.run %Q{
		CREATE TABLE #{t.name} as 
		SELECT 
			DISTINCT
			a.situsid as property_id,
			a.primesitus::boolean as is_primary,
			a.hsnbr as addr_housenumber,
			a.hssub as addr_unit,
			a.street as addr_street,
			a.stcity as addr_city,
			a.zp1 as addr_postcode,
			a.the_geom
		FROM clark_addrs_orig a
	}
end