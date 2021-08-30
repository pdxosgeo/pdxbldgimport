
desc "Generate final address table"
table :pdx_addrs => [:master_address] do |t|
 t.drop_table
 t.run %Q{
  CREATE TABLE pdx_addrs AS
   SELECT distinct  
    state_id,
    house as housenumber,
    fulladd as street,
    a.zip as postcode,
    initcap(mail_city) as city,
    'OR'::varchar(2) as state,
    'US'::varchar(2) as country,
    a.the_geom
  FROM master_address a
  WHERE unit_no IS NULL;

  ALTER table #{t.name}
    ADD COLUMN address_id serial ;
  }
  t.add_update_column
  t.add_spatial_index(:the_geom)
  t.add_index :state_id
  t.add_index :address_id

  # do some additional clean-up
  t.run %Q{
    DELETE FROM 
    pdx_addrs a
    USING pdx_addrs b
    WHERE a.state_id=b.state_id 
      AND a.housenumber=b.housenumber
      AND a.street<>b.street
      AND a.street IN (
      'Northeast Portland Boulevard',
      'North Portland Boulevard',
      'Northeast 39th Avenue',
      'Southeast 39th Avenue'
      );

    UPDATE pdx_addrs
      SET street=
      CASE street
      WHEN 'Northeast Cesar E Chavez Boulevard'
        THEN 'Northeast César E. Chávez Boulevard'
      WHEN 'Southeast Cesar E Chavez Boulevard'
        THEN 'Southeast César E. Chávez Boulevard'
      ELSE street
      END
      WHERE street like '%Cesar E Chavez%';

  }

end

table :cities => shapefile("cty_fill.shp") do |t|
  t.drop_table
  t.load_shapefile(t.prerequisites.first, :append => false)
  t.add_update_column
end

