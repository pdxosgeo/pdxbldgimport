desc "load all clark county shapes"
task :all_clark => [:clark_bldgs_orig, :clark_addrs_orig, :clark_qtr_sec]

desc "load clark taxlots" 
table :clark_taxlots => [shapefile("clark/TaxlotsPublic.shp"),:clark_bldgs_orig, :clark_addrs_orig] do |t|
	t.drop_table?
	t.load_shapefile(t.prerequisites.first, :append => false)
	t.run %Q{
		ALTER TABLE #{t.name}
		ADD COLUMN no_addrs integer default 0,
		ADD COLUMN no_bldgs integer default 0,
		ADD COLUMN max_bldg_area numeric,
		ADD COLUMN total_bldg_area numeric;

		
		WITH bldg_count as (
			SELECT t.prop_id
				,count(1) 
				,max(st_area(st_transform(b.the_geom,3692))) as max_bldg_area
				,sum(st_area(st_transform(b.the_geom,3692))) as total_bldg_area
			FROM 
			#{t.name} t
			JOIN clark_bldgs_orig b
			  ON ST_Intersects(t.the_geom,b.the_geom_centroids)
			group by t.prop_id
		)
		UPDATE #{t.name} t
			set no_bldgs=b.count,
				max_bldg_area=b.max_bldg_area,
				total_bldg_area=b.total_bldg_area 
			FROM bldg_count b
			WHERE b.prop_id=t.prop_id;
		
		WITH addr_count as (
			SELECT t.prop_id,count(1) 
			FROM 
			#{t.name} t
			JOIN clark_addrs_orig b
				ON ST_Intersects(t.the_geom,b.the_geom)
			group by t.prop_id
		)
		UPDATE #{t.name} t
			set no_addrs=a.count
			FROM addr_count a
			WHERE a.prop_id=t.prop_id;
		
	}
	t.add_update_column
end



desc "load raw building footprints for Clark County"
table :clark_bldgs_orig  =>  [shapefile("clark/BuildingFootprints.shp"),:clark_addrs_orig] do |t|
	t.drop_table?
	t.load_shapefile(t.prerequisites.first, :append => false)
	t.run %Q{
		ALTER TABLE #{t.name}
		ADD COLUMN no_addrs integer,
		ADD COLUMN  addr_housenumber text,
		ADD COLUMN 	addr_unit text,
		ADD COLUMN 	addr_bldg text,
		ADD COLUMN 	addr_street text,
		ADD COLUMN 	addr_city text,
		ADD COLUMN 	addr_state char(2) default 'WA',
		ADD COLUMN 	addr_postcode text,
		ADD COLUMN qtrsec text,
		ADD COLUMN 	addr_country char(2) default 'US'
	}
	t.add_spatial_index
	t.add_centroids
	t.add_update_column
	t.add_index :prop_id
	
	t.run %Q{
		CREATE TEMP TABLE #{t.name}_bad_geom as 
		SELECT gid,st_makevalid(the_geom) as the_geom
		FROM #{t.name} 
		WHERE NOT st_isvalid(the_geom);

		DELETE FROM #{t.name}
		WHERE gid IN (
		SELECT gid FROM #{t.name}_bad_geom 
		WHERE ST_GeometryType(the_geom)='ST_MultiPolygon'
		);

		UPDATE #{t.name} o
		SET the_geom=f.the_geom
		FROM #{t.name}_bad_geom  f
		WHERE o.gid=f.gid;
}
end

table :clark_bldgs_to_taxlots => [:clark_bldgs_orig,:clark_taxlots] do |t|
	t.drop_table
	t.run %Q{
	create table #{t.name}
		AS SELECT 
		clark_bldgs_orig.gid as bldg_gid,
		clark_taxlots.gid as taxlot_gid
		FROM clark_taxlots
		JOIN clark_bldgs_orig
		ON ST_Intersects(clark_bldgs_orig.the_geom_centroids,clark_taxlots.the_geom);
	}
end
table :clark_addrs_to_taxlots => [:clark_addrs_orig,:clark_taxlots] do |t|
	t.drop_table
	t.run %Q{
	create table #{t.name}
		AS SELECT 
		clark_addrs_orig.gid as addr_gid,
		clark_taxlots.gid as taxlot_gid
		FROM clark_taxlots
	  JOIN clark_addrs_orig
		ON ST_Intersects(clark_addrs_orig.the_geom,clark_taxlots.the_geom);
	}
end
		
		
desc "process building footprints from the original for Clark County"
table :clark_bldgs  =>  [:clark_bldgs_to_taxlots,:clark_addrs_to_taxlots,:clark_taxlots,:clark_bldgs_orig] do |t|	
t.drop_table

# first, if we have a taxlot with only one address and one building, then let's use that.
# that gets us nearly half the buildings
t.run %Q{
	
	CREATE TABLE #{t.name} AS
		SELECT b.*
		FROM clark_bldgs_orig b
		JOIN clark_bldgs_to_taxlots ON (b.gid=clark_bldgs_to_taxlots.bldg_gid)
		JOIN clark_taxlots t ON (t.gid=clark_bldgs_to_taxlots.taxlot_gid)
		ON ST_Intersects(t.the_geom,b.the_geom_centroids)
		WHERE  t.no_addrs = 1 and t.no_bldgs =1;
}

	# next, take the case where we have only two buildings, but one is much smaller, 
	# then it's probably a shed or detached garage. 
	

t.run %Q{
	WITH a as (
		SELECT 
		a.hsnbr,
		a.hssub,
		a.building,
		a.street,
		a.stcity,
		a.zp1,
		t.the_geom
		from clark_taxlots t
		JOIN clark_addrs_orig a
		ON ST_Intersects(t.the_geom,a.the_geom)
		WHERE t.no_addrs=1 and t.no_bldgs=1
	)
	UPDATE #{t.name} b
	SET addr_housenumber=a.hsnbr,
	addr_unit=a.hssub,
	addr_street=a.street,
	addr_city=a.stcity,
	addr_postcode=a.zp1
	FROM a 
	WHERE ST_Intersects(a.the_geom,b.the_geom_centroids);
	
}
#======
#  
# # count the number of addresses on a property
# t.run %Q{
# 	
# 	UPDATE #{t.name} b
# 	SET no_addrs=a.count
# 	FROM (SELECT count(1),sn from clark_addrs_orig group by sn) a
# 	WHERE a.sn=b.prop_id;
# }
# 
# # first, add the primary address to properties where there is only one building
# # 
# t.run %Q{
# 	
# 	UPDATE #{t.name} b
# 	SET addr_housenumber=a.hsnbr,
# 	addr_unit=a.hssub,
# 	addr_street=a.street,
# 	addr_city=a.stcity,
# 	addr_postcode=a.zp1
# 	FROM clark_addrs_orig a
# 	WHERE sn=b.prop_id
# 	AND a.primesitus=1;
# }
# # next update the buildings based on where the address point is
# 
# 
# 
# t.run %Q{
# 		
# 		UPDATE #{t.name} b
# 		SET addr_housenumber=a.hsnbr,
# 		addr_unit=a.hssub,
# 		addr_street=a.street,
# 		addr_city=a.stcity,
# 		addr_postcode=a.zp1
# 		FROM clark_addrs_orig a
# 		WHERE ST_Intersects(b.the_geom,a.the_geom)
# 		AND sn=b.prop_id
# 	  AND a.primesitus=1;
# }
# 
# # then match by the property id those that we didn't get before. This updates all of them
# # which we clean up later.
# t.run %Q{
# 	--WITH n as (
# 	-- select distinct prop_id from #{t.name} where addr_street IS NOT NULL
# 	-- )
# 		UPDATE #{t.name} b
# 		SET addr_housenumber=a.hsnbr,
# 		addr_unit=a.hssub,
# 		addr_street=a.street,
# 		addr_city=a.stcity,
# 		addr_postcode=a.zp1
# 		FROM clark_addrs_orig a --, n
# 		WHERE b.prop_id=a.sn
# 		-- AND b.prop_id NOT IN (select prop_id from n) 
# 		and a.primesitus=1
# 		AND b.no_addrs=1
# 		AND b.addr_street IS NULL
# 		;
# 
# }
# 
# # Now we null out everything that has an address, but isn't the biggest building
# t.run %Q{
# 
# 		WITH max_area as (
# 			SELECT max(shape_area) as area, prop_id
# 			FROM #{t.name} 
# 				WHERE prop_id in (
# 				SELECT prop_id 
# 				FROM #{t.name} 
# 					WHERE addr_street IS NOT NULL
# 					AND no_addrs = 1
# 					GROUP by prop_id
# 					HAVING count(1)>1
# 				)
# 			GROUP BY prop_id
# 		)
# 		UPDATE #{t.name}  a
# 		SET 
# 				addr_housenumber = NULL,
# 				addr_unit = NULL,
# 				addr_street = NULL,
# 				addr_city = NULL,
# 				addr_postcode = NULL,
# 				addr_state = NULL,
# 				addr_country = NULL
# 		FROM max_area
# 		WHERE a.prop_id=max_area.prop_id
# 		AND a.shape_area<>max_area.area;
# 		}
# 	
# 	t.run %Q{
# 		UPDATE #{t.name} b
# 		SET qtrsec=q.quarter
# 		FROM clark_qtr_sec q
# 		WHERE st_intersects(q.the_geom,b.the_geom_centroids);
# 	}	
# 	

	t.add_spatial_index
	t.add_update_column
end

desc "load raw address points for Clark County"
table :clark_addrs_orig  =>  shapefile("clark/Situs.shp") do |t|
	t.drop_table?
	t.load_shapefile(t.prerequisites.first, :append => false)
	t.run %Q{
		ALTER TABLE #{t.name}
			ADD COLUMN street text;

		UPDATE #{t.name}
			SET 
			stcity = initcap(stcity),
			stname = initcap(regexp_replace(stname, '^Mt ','Mount ', 'i')),
			stdir = CASE stdir
				WHEN 'E' THEN 'East'
				WHEN 'W' THEN 'West'
				WHEN 'S' THEN 'South'
				WHEN 'N' THEN 'North'
				WHEN 'NW' THEN 'Northwest'
				WHEN 'NE' THEN 'Northeast'
				WHEN 'SW' THEN 'Southwest'
				WHEN 'SE' THEN 'Southeast'
				ELSE stdir
				END,
				stype=CASE stype
				WHEN 'ALY' THEN 'Alley'
				WHEN 'AVE' THEN 'Avenue'
				WHEN 'BLVD' THEN 'Boulevard'
				WHEN 'BRG' THEN 'Bridge'
				WHEN 'CIR' THEN 'Circle'
				WHEN 'CMN' THEN 'Common'
				WHEN 'CR' THEN 'Creek'
				WHEN 'CRES' THEN 'Crest'
				WHEN 'CRST' THEN 'Crescent'
				WHEN 'CT' THEN 'Court'
				WHEN 'DR' THEN 'Drive'
				WHEN 'FWY' THEN 'Freeway'
				WHEN 'HWY' THEN 'Highway'
				WHEN 'LN' THEN 'Lane'
				WHEN 'LOOP' THEN 'Loop'
				WHEN 'LP' THEN 'Loop'
				WHEN 'PARK' THEN 'Park'
				WHEN 'PATH' THEN 'Path'
				WHEN 'PKWY' THEN 'Parkway'
				WHEN 'PL' THEN 'Place'
				WHEN 'PT' THEN 'Point'
				WHEN 'RD' THEN 'Road'
				WHEN 'RDG' THEN 'Ridge'
				WHEN 'ROW' THEN 'Row'
				WHEN 'SQ' THEN 'Square'
				WHEN 'ST' THEN 'Street'
				WHEN 'TER' THEN 'Terrace'
				WHEN 'TERR' THEN 'Terrace'
				WHEN 'VW' THEN 'View'
				WHEN 'WALK' THEN 'Walk'
				WHEN 'WAY' THEN 'Way'
				WHEN 'WY' THEN 'Way'
				ELSE stype
				END;
				
				UPDATE #{t.name}
					SET stname='Mac'||initcap(regexp_replace(stname, '^Mac',''))
					WHERE stname like 'Mac%';
				UPDATE #{t.name}
					SET stname='Mc'||initcap(regexp_replace(stname, '^Mc',''))
					WHERE stname like 'Mc%';				
				
				UPDATE #{t.name} 
					SET street=CONCAT_WS(' ', stdir, stname, stype);
	}
	t.add_spatial_index
	t.add_update_column
end

desc "load qtrsecs for Clark County"
table :clark_qtr_sec  =>  shapefile("clark/qsection.shp") do |t|
	t.drop_table?
	t.load_shapefile(t.prerequisites.first, :append => false)
	t.add_spatial_index
	t.add_update_column
end
