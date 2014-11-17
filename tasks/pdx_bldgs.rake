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
    --ALTER TABLE #{t.name} ALTER the_geom type geometry(MultiPolygon,4326) using st_multi(the_geom);
    DELETE FROM #{t.name} WHERE NOT st_isvalid(the_geom);

--    UPDATE #{t.name}
--      SET the_geom=st_makevalid(the_geom) 
--      WHERE not st_isvalid(the_geom);

    UPDATE  #{t.name} 
      SET state_id=regexp_replace(state_id, E'(\s|-0*)','','g');

    ALTER TABLE #{t.name}
      RENAME COLUMN gid to pdx_bldg_id;

  }
  t.add_centroids
  t.add_index :state_id
end

desc "Generate final format building footprint data"
table :pdx_bldgs => [:pdx_bldgs_orig, :pdx_addrs, :osm_buildings] do |t|
  t.drop_table
  t.run %Q{
  CREATE TEMP TABLE house_and_garage AS
  SELECT DISTINCT a.state_id
   from  pdx_bldgs_orig a
    JOIN pdx_bldgs_orig b on (a.state_id=b.state_id)
    WHERE a.state_id in (select state_id from pdx_bldgs_orig group by state_id having count(1)=2)
    AND (
      (a.bldg_type='House' and b.bldg_type='Garage')
      OR
      (b.bldg_type='House' and a.bldg_type='Garage')
    );
    
  CREATE table pdx_bldgs as 
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
    round(b.surf_elev::numeric * 0.3048,2) as ele,
    round(b.max_height::numeric * 0.3048,2) as height,
    CASE b.bldg_type
      WHEN 'Townhouse' THEN 'house'
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
    CASE a.state_id IS NULL WHEN true THEN 0::integer ELSE 1::integer END as no_addrs,
    the_geom_centroids,
    st_multi(ST_SimplifyPreserveTopology(b.the_geom,0.000001))::geometry(MultiPolygon,4326) as the_geom
  FROM pdx_bldgs_orig b
  LEFT OUTER JOIN pdx_addrs a on (a.state_id=b.state_id)
  WHERE b.state_id IN (select state_id from pdx_bldgs_orig group by state_id having count(1)=1)
  OR b.state_id IN (SELECT state_id FROM house_and_garage);
  
  UPDATE #{t.name}
    SET address_id=NULL, housenumber=NULL,street=NULL 
    WHERE bldg_type='Garage' 
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
    address_id =NULL
    WHERE bldg_type='Garage'
    AND state_id in (SELECT state_id FROM house_and_garage);


  UPDATE #{t.name}
    SET qtrsec = conslidated_qtr_secs.qtrsec
    FROM conslidated_qtr_secs
    WHERE st_intersects(conslidated_qtr_secs.the_geom,pdx_bldgs.the_geom_centroids);

  }

  t.add_update_column
end
