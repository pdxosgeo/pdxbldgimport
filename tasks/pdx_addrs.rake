desc "Generate final address table"
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

desc "Load raw address data. Used to generate pdx_addrs"
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
      SET the_geom=st_transform(st_setsrid(ST_MakePoint("x"::numeric,"y"::numeric),2913),4326),
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