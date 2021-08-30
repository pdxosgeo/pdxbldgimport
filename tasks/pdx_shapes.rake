file 'buildings.zip' do 
  sh %Q{ wget --quiet --timestamping http://library.oregonmetro.gov/rlisdiscovery/buildings.zip }
end 

bldg_date=File.stat('buildings.zip').mtime.strftime('%Y-%m-%d')
#bldg_date='2021-01-21'

file "PortlandBuildings-#{bldg_date}/buildings.shp" => 'buildings.zip' do
  sh %Q{unzip -n -j buildings.zip -d PortlandBuildings-#{bldg_date};true}
  # we have to do this, because the individual files are newer than the zipfile that contains them
  sh %Q{touch -t #{(File.stat('buildings.zip').mtime+1).strftime('%Y%m%d%H%M.%S')}  PortlandBuildings-#{bldg_date}/*}
end

desc "Dowloads and unzips the latest building footprints"
task :pdx_bldg_download => "PortlandBuildings-#{bldg_date}/buildings.shp" do
end
file 'master_address.zip' do 
sh %Q{ wget --quiet --timestamping http://library.oregonmetro.gov/rlisdiscovery/master_address.zip }
end 

addr_date=File.stat('master_address.zip').mtime.strftime('%Y-%m-%d')

file "PortlandAddrs-#{addr_date}/master_address.shp" => 'master_address.zip' do
sh %Q{unzip -n -j master_address.zip -d PortlandAddrs-#{addr_date};true}
# we have to do this, because the individual files are newer than the zipfile that contains them
sh %Q{touch -t #{(File.stat('master_address.zip').mtime+1).strftime('%Y%m%d%H%M.%S')}  PortlandAddrs-#{addr_date}/*}
end

desc "Dowloads and unzips the latest address file"
task :pdx_addr_download => "PortlandAddrs-#{addr_date}/master_address.shp" do
end

table :master_address => shapefile("PortlandAddrs-#{addr_date}/master_address.shp") do |t|
t.drop_table
t.load_shapefile(t.prerequisites.first, :append => false)
t.run %Q{
  ALTER TABLE #{t.name}  ADD COLUMN state_id text;
  UPDATE #{t.name}
    SET 
    state_id=regexp_replace(tlid, E'(\s|-0*)','','g'),
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
      WHEN 'ALY' THEN 'Alley'
      WHEN 'AVE' THEN 'Avenue'
      WHEN 'BLVD' THEN 'Boulevard'
      WHEN 'BRG' THEN 'Bridge'
      WHEN 'CIR' THEN 'Circle'
      WHEN 'CIRC' THEN 'Circle'
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
      WHEN 'SQ' THEN 'Square'
      WHEN 'ST' THEN 'Street'
      WHEN 'TER' THEN 'Terrace'
      WHEN 'TERR' THEN 'Terrace'
      WHEN 'VW' THEN 'View'
      WHEN 'WALK' THEN 'Walk'
      WHEN 'WAY' THEN 'Way'
      WHEN 'WY' THEN 'Way'
      ELSE ftype
      END;
  UPDATE #{t.name}
    SET fname=regexp_replace(fname,'Hwy', 'Highway') 
    WHERE fname ~* E'(^|\s+)hwy ';

  UPDATE #{t.name}
    SET fulladd=array_to_string(ARRAY[fdpre,fname,ftype,fdsuf], ' ')
}
t.add_update_column
t.add_index :state_id
t.add_index :tlid
end


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
   }

   t.run %Q{   
    UPDATE #{t.name}
      SET bldg_type='Res'
      WHERE (bldg_type is null OR bldg_type='Not Set')
      and (bldg_use ilike '%Residential%' OR bldg_use ilike '%house%')
   }

  t.run %Q{
    ALTER TABLE #{t.name}
      RENAME state_id TO tlid;
  }

  t.run %Q{
    ALTER TABLE #{t.name}
      ADD COLUMN state_id text;
  }
  t.run %Q{
    UPDATE  #{t.name} 
      SET state_id=regexp_replace(tlid, E'(\s|-0*)','','g');
  }
  t.run %Q{
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

