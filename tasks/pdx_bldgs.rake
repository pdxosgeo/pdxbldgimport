desc "Generate final format building footprint data"
table :pdx_bldgs => [:pdx_bldgs_orig, :pdx_addrs, :osm_buildings, :addr_bldg_counts] do |t|
  t.drop_table
  t.run %Q{
  -- first we find the buildings that are a house
  -- with a detached garage so we can include
  -- them even though there are two buildings
  -- on the property
  -- for testing, state_id = '1N1E16BD7100'
  -- has two addrs, and a house and garage

  CREATE TEMP TABLE house_and_garage AS
  SELECT DISTINCT a.state_id,addr_count
   from  pdx_bldgs_orig a
    JOIN pdx_bldgs_orig b on (a.state_id=b.state_id)
    JOIN addr_bldg_counts abc ON (a.state_id=abc.state_id)
    WHERE abc.bldg_count=2
    AND (
      (a.bldg_type ilike 'House%' and b.bldg_type ilike 'Garage')
      OR
      (b.bldg_type ilike 'House%' and a.bldg_type ilike 'Garage')
    )
  ;

  -- CREATE temp view with all of our possible
  -- attributes, for later resuse
  CREATE OR REPLACE TEMP VIEW pdx_bldg_view AS 
    SELECT b.state_id,
    b.bldg_id,
    b.pdx_bldg_id,
    a.address_id,
    a.housenumber,
    a.street,
    a.postcode,
    a.city,
    a.state,
    a.country,
    ''::text as qtrsec,
    b.num_story as levels,
    round(b.surf_elev::numeric * 0.3048,1) as ele,
    round(b.max_height::numeric * 0.3048,1) as height,
    CASE b.bldg_type
      WHEN 'House' THEN 'detached'
      WHEN 'HOUSES' THEN 'detached'
      WHEN 'Houses' THEN 'detached'
      WHEN 'Garage' THEN 'garage'
      WHEN 'RES' THEN 'residential'
      WHEN 'Res' THEN 'residential'
      WHEN 'Duplex' THEN 'apartments'
      WHEN 'Townhouse' THEN 'apartments'
      WHEN 'Apartment Complex' THEN 'apartments'
      WHEN 'Multiplex' THEN 'apartments'
      WHEN 'Residential Condominiums' THEN 'apartments'
      WHEN 'Dormitories' THEN 'dormitory'
      ELSE 'yes' END as bldg_type,
    coalesce(abc.addr_count,0) as no_addrs,
    coalesce(abc.bldg_count,0) as bldg_count,
    false::boolean as is_deleted,
    the_geom_centroids,
    st_multi(ST_SimplifyPreserveTopology(b.the_geom,0.000001))::geometry(MultiPolygon,4326) as the_geom
  FROM pdx_bldgs_orig b
  LEFT OUTER JOIN pdx_addrs a on (a.state_id=b.state_id)
  JOIN addr_bldg_counts abc on (abc.state_id=a.state_id);


  -- extract all buildings that
  -- have zero or one address associated
  -- *or* that are in the list of 
  -- buildings/garages above
  CREATE table pdx_bldgs as 
    SELECT * FROM pdx_bldg_view
    WHERE (
      no_addrs<=1
    OR 
      state_id IN (SELECT state_id FROM house_and_garage where addr_count<=1)
    );
  }

t.run %Q{
  -- now insert just building footprints
  -- for things, including garages and houses
  -- that have more than one address
  INSERT INTO pdx_bldgs(state_id,bldg_id,pdx_bldg_id,
                      qtrsec,levels,ele,height,
                      bldg_type,bldg_count,no_addrs,
                      the_geom_centroids,
                      the_geom)
  SELECT DISTINCT state_id,
    bldg_id,
    pdx_bldg_id,
    ''::text,
    levels,ele,
    height,
    bldg_type,
    bldg_count,
    no_addrs,
    the_geom_centroids,
    the_geom
  FROM pdx_bldg_view
  WHERE (
    no_addrs>1
    AND
    bldg_count=1
    )
    OR (state_id IN (SELECT state_id FROM house_and_garage where addr_count>1));
  }
 
  t.run %Q{
    UPDATE #{t.name}
    SET address_id=NULL, 
    housenumber=NULL,
    street=NULL,
    city = NULL,
    postcode = NULL,
    state = NULL
    WHERE bldg_type ILIKE 'garage' 
    AND address_id IS NOT NULL;
  }

  t.add_spatial_index(:the_geom)
  t.add_spatial_index(:the_geom_centroids)
  t.add_index(:address_id)
  t.add_index(:bldg_id)
  t.add_index(:no_addrs)
  
  t.run %Q{
    UPDATE #{t.name}
    SET housenumber = NULL,
    street = NULL,
    address_id =NULL,
    city = NULL,
    postcode = NULL,
    state = NULL
    WHERE bldg_type ILIKE 'garage'
    AND state_id in (SELECT state_id FROM house_and_garage);
  }
  

  t.run %Q{
    UPDATE #{t.name}
      SET qtrsec = q.qtrsec
      FROM qtr_sec q
      WHERE st_intersects(q.the_geom,pdx_bldgs.the_geom_centroids);
  }

  t.run %Q{
    ALTER TABLE #{t.name} ADD column area numeric;

    UPDATE #{t.name} SET area=st_area(st_transform(the_geom, 2913));
  }
  t.run %Q{
    WITH max_area as (
      SELECT max(area) as area, state_id
      FROM #{t.name} 
        WHERE state_id in (
        SELECT state_id 
        FROM pdx_bldgs
          WHERE street IS NOT NULL
          AND no_addrs = 1
          GROUP by state_id
          HAVING count(1)>1
        )
      GROUP BY state_id
    )
    UPDATE #{t.name} a
    SET housenumber = NULL,
        street = NULL,
        address_id =NULL,
        city = NULL,
        postcode = NULL,
        state = NULL
    FROM max_area
    WHERE a.state_id=max_area.state_id
    AND a.area<>max_area.area;
  }
  t.add_update_column
end

# -- playing around here, not working at the moment
#  -- CREATE TEMP TABLE addr_fix as
#  --  WITH c as (select count(1),state_id from pdx_addrs group by state_id having count(1)=1)
#  --  SELECT b.pdx_bldg_id,a.* FROM pdx_addrs a, pdx_bldgs b,c
#  -- 	where 
#  -- 		b.street is null
#  -- 		AND a.state_id=b.state_id 
#  -- 		and c.state_id=a.state_id
#  -- 		and st_intersects(a.the_geom,b.the_geom)
#  -- 		and a.address_id not in (select address_id from pdx_bldgs);
#  -- 	
#  -- 	UPDATE #{t.name} b
#  -- 	SET housenumber=a.housenumber,
#  -- 		street=a.street,
#  -- 		postcode=a.postcode,
#  -- 		city=a.city,
#  -- 		state=a.state
#  -- 		country=a.country
#  -- 	FROM addr_fix a
#  -- 	WHERE a.state_id=b.state_id;
#  -- 	
#  --  
#  
