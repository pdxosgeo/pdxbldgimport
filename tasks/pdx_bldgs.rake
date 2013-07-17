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
            :master_address => 'master_address.shp'
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
    ALTER TABLE #{t.name} ADD COLUMN tlid varchar(20);
    ALTER TABLE #{t.name} ADD COLUMN neighborhood varchar(60);
    UPDATE #{t.name} SET the_geom=st_makevalid(the_geom) WHERE NOT st_isvalid(the_geom);
    UPDATE #{t.name} b SET tlid=t.tlid FROM taxlots t WHERE st_intersects(b.the_geom_centroids,t.the_geom);
  }
  t.add_centroids
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
table :pdx_addrs => [:master_address] do |t|
 t.drop_table
 t.run %Q{
CREATE TABLE pdx_addrs AS
 SELECT distinct on (tlid,housenumber,street,postcode)
  tlid,
  house as housenumber,
  array_to_string(ARRAY[a.fdpre,a.fname,a.ftype,a.fdsuf],' ') as street,
  nbo_hood.name as neighborhood,
  a.zip as postcode,
  initcap(a.juris_city) as city,
  'OR'::varchar(2) as state,
  'US'::varchar(2) as country,
  a.the_geom
FROM master_address a
LEFT OUTER JOIN nbo_hood on st_intersects(nbo_hood.the_geom,a.the_geom);
CREATE INDEX ON pdx_addrs (tlid);
CREATE INDEX ON pdx_addrs using gist(the_geom);
}
t.add_update_column
end

task :master_address do |t|
  t.run %Q{
    ALTER TABLE master_address ALTER column fdpre type varchar(10);
    ALTER TABLE master_address ALTER column fdsuf type varchar(10);
    ALTER TABLE master_address ALTER column ftype type varchar(20);

    # make the prefixes/suffixes match silly OSM rules
    UPDATE master_address SET
      fname=initcap(regexp_replace(fname, E'"','','g')),
      fdpre=CASE fdpre
        WHEN 'N' THEN 'North'
        WHEN 'S' THEN 'South'
        WHEN 'E' THEN 'East'
        WHEN 'W' Then 'West'
        WHEN 'NW' THEN 'Northwest'
        WHEN 'SW' THEN 'Southwest'
        WHEN 'NE' THEN 'Northeast'
        WHEN 'SE' THEN 'Southeast'
        END,
      fdsuf=CASE fdsuf
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
      ftype=CASE ftype
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
  }
end

