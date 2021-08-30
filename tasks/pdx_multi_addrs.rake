
table :pdx_bldgs_multi_addrs => [:pdx_bldgs, :pdx_addrs] do |t|
	t.drop_table
	t.run %Q{

		CREATE or REPLACE FUNCTION perturb_point(pt geometry) returns geometry AS $$
			DECLARE
				srid integer;
				offset_x double precision;
				offset_y double precision;
			BEGIN
				offset_y:=random()*0.00001;
				offset_x:=random()*0.00001;
				srid:=st_srid(pt);
				pt:=st_setsrid(st_makepoint(st_x(pt)+offset_x, st_y(pt)+offset_y), srid);
				RETURN pt;
			END;
		$$ language plpgsql;


		-- if the addresses are contained entirely inside the 
		-- building, just use the points from the city
		CREATE TABLE #{t.name} AS
		SELECT 
			b.pdx_bldg_id,
			b.state_id,
			b.qtrsec,
			a.housenumber,
			a.street,
			a.postcode,
			a.city,
			a.state,
			a.the_geom
		FROM pdx_bldgs b
		JOIN pdx_addrs a ON a.state_id=b.state_id
		WHERE no_addrs>1
		and is_deleted=false
		AND pdx_bldg_id IN (
			SELECT b.pdx_bldg_id
			FROM pdx_bldgs b
			JOIN pdx_addrs a ON st_intersects(b.the_geom,a.the_geom)
			WHERE no_addrs>1
			GROUP BY pdx_bldg_id
			having count(1)=avg(no_addrs)
		);

		-- for those that don't have all the addresses
		-- inside the building, place them randomly 
		-- inside the footprint (remember, pdx_bldgs
		-- only includes lots with one building, or those
		-- with one building and a garage)
		WITH a AS (
			SELECT row_number()  over (PARTITION BY state_id ORDER BY housenumber) as num,
				housenumber,
				street,
				postcode,
				city,
				state,
				state_id 
			FROM pdx_addrs 
		),
		b AS (
			SELECT generate_series(1, no_addrs) as num 
			, qtrsec
			, state_id
			, pdx_bldg_id
			, ST_PointOnSurface(the_geom) as the_geom
			from pdx_bldgs 
			where no_addrs>1
			and is_deleted=false
			-- make sure we don't duplicate
			-- our addresses inside of our garages
			and bldg_type <> 'garage' 
		)
		INSERT INTO #{t.name}
		SELECT 
			b.pdx_bldg_id,
			b.state_id,
			b.qtrsec,
			a.housenumber,
			a.street,
			a.postcode,
			a.city,
			a.state,
			b.the_geom
		FROM a NATURAL JOIN b
		WHERE state_id NOT IN (SELECT state_id FROM #{t.name});

		UPDATE #{t.name}
			SET the_geom = perturb_point(the_geom);
	}
	
	t.add_spatial_index :the_geom
	t.add_update_column

end