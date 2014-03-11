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
  run %Q{
    UPDATE #{t.name}
      SET 
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
      SET fulladd=array_to_string(ARRAY[fdpre,fname,ftype,fdsuf], ' ')
  }
end

desc "Generate final address table"
table :pdx_addrs => [:master_address] do |t|
 t.drop_table
 t.run %Q{
  CREATE TABLE pdx_addrs AS
   SELECT distinct
    tlid as state_id,
    house as housenumber,
    fulladd as street,
    a.zip as postcode,
    initcap(mail_city) as city,
    'OR'::varchar(2) as state,
    'US'::varchar(2) as country,
    a.the_geom
  FROM master_address a;

  ALTER table #{t.name}
    ADD COLUMN address_id serial ;
  }
  t.add_update_column
  t.add_spatial_index(:the_geom)
  t.add_index :state_id
  t.add_index :address_id

end


