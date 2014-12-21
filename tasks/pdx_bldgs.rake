file 'buildings.zip' do 
  sh %Q{ wget --quiet --timestamping http://library.oregonmetro.gov/rlisdiscovery/buildings.zip }
end 

bldg_date=File.stat('buildings.zip').mtime.strftime('%Y-%m-%d')

file "PortlandBuildings-#{bldg_date}/buildings.shp" => 'buildings.zip' do
  sh %Q{unzip -n -j buildings.zip -d PortlandBuildings-#{bldg_date};true}
  # we have to do this, because the individual files are newer than the zipfile that contains them
  sh %Q{touch -t #{(File.stat('buildings.zip').mtime+1).strftime('%Y%m%d%H%M.%S')}  PortlandBuildings-#{bldg_date}/*}
end

desc "Dowloads and unzips the latest building footprints"
task :pdx_bldg_download => "PortlandBuildings-#{bldg_date}/buildings.shp" do
end

desc "Run all building and address related tasks"
task :all_pdx => [:pdx_bldgs, :pdx_addrs, :qtr_sec]

desc "load raw building footprints. Used only by :pdx_bldgs tasks"
table :pdx_bldgs_orig  =>  shapefile("PortlandBuildings-#{bldg_date}/buildings.shp") do |t|
  t.drop_table
  t.load_shapefile(t.prerequisites.first, :append => false)
  t.run %Q{

    CREATE TEMP TABLE pdx_bldgs_orig_bad_geom as 
      SELECT gid,st_makevalid(the_geom) as the_geom
      FROM pdx_bldgs_orig 
      WHERE NOT st_isvalid(the_geom);

    DELETE FROM #{t.name}
      WHERE gid IN (
        SELECT gid FROM pdx_bldgs_orig_bad_geom
        WHERE ST_GeometryType(the_geom)='ST_MultiPolygon'
        );
    
    UPDATE #{t.name} o
      SET the_geom=f.the_geom
      FROM pdx_bldgs_orig_bad_geom f
      WHERE o.gid=f.gid;

    ALTER TABLE #{t.name}
      RENAME state_id TO tlid;

    ALTER TABLE #{t.name}
      ADD COLUMN state_id text;

    UPDATE  #{t.name} 
      SET state_id=regexp_replace(tlid, E'(\s|-0*)','','g');

    ALTER TABLE #{t.name}
      RENAME COLUMN gid to pdx_bldg_id;

  }
  t.add_centroids
  t.add_index :state_id
end

desc "Table counting number of bldgs and addresses"
table :addr_bldg_counts => [:pdx_bldgs_orig, :pdx_addrs] do |t|
  t.drop_table
  t.run %Q{
    WITH b as (SELECT count(1) as bldg_count,state_id FROM pdx_bldgs_orig GROUP by state_id),
     a as (SELECT count(1) as addr_count,state_id FROM pdx_addrs GROUP BY state_id)
    SELECT
    bldg_count,addr_count,a.state_id
    INTO addr_bldg_counts
    FROM a NATURAL JOIN b;
  }
  t.add_update_column
  t.add_index :state_id, :unique => true
end

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
      (a.bldg_type ilike 'House' and b.bldg_type ilike 'Garage')
      OR
      (b.bldg_type ilike 'House' and a.bldg_type ilike 'Garage')
    )
  ;

  -- CREATE temp view with all of our possible
  -- attributes, for later resuse
  CREATE TEMP VIEW pdx_bldg_view AS 
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
      WHEN 'Garage' THEN 'garage'
      WHEN 'RES' THEN 'residential'
      WHEN 'Res' THEN 'residential'
      WHEN 'Duplex' THEN 'apartments'
      WHEN 'Apartment Complex' THEN 'apartments'
      WHEN 'Multiplex' THEN 'apartments'
      WHEN 'Residential Condominiums' THEN 'apartments'
      WHEN 'Dormitories' THEN 'dormitory'
      ELSE 'yes' END as bldg_type,
    coalesce(abc.addr_count,0) as no_addrs,
    coalesce(abc.bldg_count,0) as bldg_count,
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



  -- now insert just building footprints
  -- for things, including garages and houses
  -- that have more than one address
  INSERT INTO pdx_bldgs(state_id,bldg_id,pdx_bldg_id,
                      qtrsec,levels,ele,height,
                      bldg_type,no_addrs,
                      the_geom_centroids,
                      the_geom)
  SELECT DISTINCT state_id,
    bldg_id,
    pdx_bldg_id,
    ''::text,
    levels,ele,
    height,
    bldg_type,no_addrs,
    the_geom_centroids,
    the_geom
  FROM pdx_bldg_view
  WHERE (
    no_addrs>1
    AND
    bldg_count=1
    )
    OR (state_id IN (SELECT state_id FROM house_and_garage where addr_count>1));
 
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
    DELETE FROM #{t.name} a
    USING osm_buildings b
    where st_intersects(a.the_geom,b.the_geom);
    
    UPDATE #{t.name}
    SET housenumber = NULL,
    street = NULL,
    address_id =NULL,
    city = NULL,
    postcode = NULL,
    state = NULL
    WHERE bldg_type ILIKE 'garage'
    AND state_id in (SELECT state_id FROM house_and_garage);


  UPDATE #{t.name}
    SET qtrsec = conslidated_qtr_secs.qtrsec
    FROM conslidated_qtr_secs
    WHERE st_intersects(conslidated_qtr_secs.the_geom,pdx_bldgs.the_geom_centroids);

  }
  t.run %Q{
    ALTER TABLE #{t.name} ADD column area numeric;

    UPDATE #{t.name} SET area=st_area(st_transform(the_geom, 2913));

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
    UPDATE #{t.name}  a
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
      , st_centroid(the_geom) as the_geom
      from pdx_bldgs 
      where no_addrs>1
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