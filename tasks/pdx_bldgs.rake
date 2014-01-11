file 'Building_Footprints_pdx.zip' do 
  sh %Q{ wget --quiet --timestamping ftp://ftp02.portlandoregon.gov/CivicApps/Building_Footprints_pdx.zip }
end 

bldg_date=File.stat('Building_Footprints_pdx.zip').mtime.strftime('%Y-%m-%d')

file "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp" => 'Building_Footprints_pdx.zip' do
  sh %Q{unzip -n -j Building_Footprints_pdx.zip -d PortlandBuildings-#{bldg_date};true}
  # we have to do this, because the individual files are newer than the zipfile that contains them
  sh %Q{touch -t #{(File.stat('Building_Footprints_pdx.zip').mtime+1).strftime('%Y%m%d%H%M.%S')}  PortlandBuildings-#{bldg_date}/*}
end

task :pdx_download => "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp" do
end


pdx_shapes = { 
            :pdx_bldgs_orig =>  "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp",
            :master_address => 'master_address.shp',
            :taxlots => 'taxlots.shp'
}


pdx_shape_tasks=[]
pdx_shapes.each do |k,v|
  x=table k => shapefile(v) do |t|
      t.drop_table
      t.load_shapefile(t.prerequisites.first, :append => false)
  end
  pdx_shape_tasks << x
end

task :all_pdx => [:pdx_bldgs, :pdx_addrs]

task :pdx_bldgs_orig do |t|
  t.run %Q{
    UPDATE #{t.name}
      SET the_geom=st_makevalid(the_geom) 
      WHERE not st_isvalid(the_geom);
  }
  t.add_centroids
  # t.run %Q{
  #   ALTER TABLE #{t.name} ADD COLUMN tlid varchar(20);
  #   ALTER TABLE #{t.name} ADD COLUMN neighborhood varchar(60);
  #   UPDATE #{t.name} SET the_geom=st_makevalid(the_geom) WHERE NOT st_isvalid(the_geom);
  #   UPDATE #{t.name} b SET tlid=t.tlid FROM taxlots t WHERE st_intersects(b.the_geom_centroids,t.the_geom);
  # }
end

table :pdx_bldgs => [:pdx_bldgs_orig] do |t|
  t.drop_table
  t.run %Q{
  CREATE table pdx_bldgs as 
    SELECT  b.bldg_id,
    b.tlid,
    b.num_story as levels,
    round(b.surf_elev::numeric * 0.3048,2) as ele,
    round(b.max_height::numeric * 0.3048,2) as height,
    b.bldg_name as name,
    'yes'::varchar(20) as building,
    b.bldg_use,
    0::integer as no_addrs,
    the_geom_centroids,
    the_geom
  FROM pdx_bldgs_orig b;
  } 
  t.add_spatial_index(:the_geom)
  t.add_spatial_index(:the_geom_centroids)
  t.add_index(:tlid)
  t.add_index(:bldg_id)
  t.add_update_column
end

table :pdx_addrs => [:addresses] do |t|
 t.drop_table
 t.run %Q{
  CREATE TABLE pdx_addrs AS
   SELECT distinct
    address_number as housenumber,
    address_full as street,
    a.zip_code as postcode,
    initcap(city) as city,
    'OR'::varchar(2) as state,
    'US'::varchar(2) as country,
    a.the_geom
  FROM addresses a
  WHERE the_geom is not null
  }
  t.add_update_column
  t.add_spatial_index(:the_geom)

end


table :addresses => 'address_data.csv' do |t|
  t.drop_table
  t.run %Q{
    CREATE TABLE #{t.name} (
      "address_id" varchar(20) primary key,
      "address_number" integer,
      "address_number_char" varchar(20),
      "leading_zero" varchar(1),
      "str_predir_code" varchar(20),
      "street_name" varchar(50),
      "street_type_code" varchar(20),
      "str_postdir_code" varchar(20),
      "unit_value" varchar(20),
      "city" varchar(20),
      "county" varchar(20),
      "state_abbrev" varchar(20),
      "zip_code" varchar(5),
      "zip4" varchar(4),
      "address_full" varchar(200),
      "x" varchar(20),
      "y" varchar(20))
  }
  psql("\\copy #{t.name} FROM #{t.prerequisites.first} CSV HEADER ")
  t.add_point_column
  t.run %Q{
    UPDATE #{t.name}
      SET x=NULLIF(x,''),y=NULLIF(y,'');

    UPDATE #{t.name}
      SET the_geom=st_transform(st_setsrid(ST_MakePoint("x"::numeric,"y"::numeric),2319),4326),
      street_name=initcap(regexp_replace(street_name, E'"','','g')),
      str_predir_code=CASE str_predir_code
        WHEN 'N' THEN 'North'
        WHEN 'S' THEN 'South'
        WHEN 'E' THEN 'East'
        WHEN 'W' Then 'West'
        WHEN 'NW' THEN 'Northwest'
        WHEN 'SW' THEN 'Southwest'
        WHEN 'NE' THEN 'Northeast'
        WHEN 'SE' THEN 'Southeast'
        END,
      str_postdir_code=CASE str_postdir_code
        WHEN 'N' THEN 'North'
        WHEN 'S' THEN 'South'
        WHEN 'E' THEN 'East'
        WHEN 'W' Then 'West'
        WHEN 'NW' THEN 'Northwest'
        WHEN 'SW' THEN 'Southwest'
        WHEN 'NE' THEN 'Northeast'
        WHEN 'SE' THEN 'Southeast'
        WHEN 'SB' THEN 'Southbound'
        WHEN 'NB' THEN 'Northbound'
        END,
      street_type_code=CASE street_type_code
        WHEN 'BRG' THEN 'Bridge'
        WHEN 'CR' THEN 'Creek'
        WHEN 'FWY' THEN 'Freeway'
        WHEN 'LOOP' THEN 'Loop'
        WHEN 'PARK' THEN 'Park'
        WHEN 'RDG' THEN 'Ridge'
        WHEN 'PT' THEN 'Point'
        WHEN 'ST' THEN 'Street'
        WHEN 'RD' THEN 'Road'
        WHEN 'PL' THEN 'Place'
        WHEN 'WAY' THEN 'Way'
        WHEN 'DR' THEN 'Drive'
        WHEN 'BLVD' THEN 'Boulevard'
        WHEN 'SQ' THEN 'Square'
        WHEN 'LN' THEN 'Lane'
        WHEN 'CT' THEN 'Court'
        WHEN 'TER' THEN 'Terrace'
        WHEN 'PKWY' THEN 'Parkway'
        WHEN 'CIR' THEN 'Circle'
        WHEN 'HWY' THEN 'Highway'
        WHEN 'AVE' THEN 'Avenue'
        WHEN 'CRES' THEN 'Crest'
        WHEN 'PATH' THEN 'Path'
        WHEN 'ALY' THEN 'Alley'
        WHEN 'WALK' THEN 'Walk'
        WHEN 'CRST' THEN 'Crescent'
        END;
    UPDATE #{t.name}
      SET address_full=array_to_string(ARRAY[address_number_char,str_predir_code,street_name,street_type_code,str_postdir_code], ' ')
  }

  t.add_update_column
end

