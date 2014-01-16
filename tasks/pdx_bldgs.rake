file 'Building_Footprints_pdx.zip' do 
  sh %Q{ wget --quiet --timestamping ftp://ftp02.portlandoregon.gov/CivicApps/Building_Footprints_pdx.zip }
end 

bldg_date=File.stat('Building_Footprints_pdx.zip').mtime.strftime('%Y-%m-%d')

file "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp" => 'Building_Footprints_pdx.zip' do
  sh %Q{unzip -n -j Building_Footprints_pdx.zip -d PortlandBuildings-#{bldg_date};true}
  # we have to do this, because the individual files are newer than the zipfile that contains them
  sh %Q{touch -t #{(File.stat('Building_Footprints_pdx.zip').mtime+1).strftime('%Y%m%d%H%M.%S')}  PortlandBuildings-#{bldg_date}/*}
end

desc "Dowloads and unzips the latest building footprints"
task :pdx_download => "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp" do
end


pdx_shapes = { 
            :pdx_bldgs_orig =>  "PortlandBuildings-#{bldg_date}/Building_Footprints_pdx.shp",
            :master_address => './rlis/TAXLOTS/master_address.shp',
            :taxlots => './rlis/TAXLOTS/taxlots.shp'
}


pdx_shape_tasks=[]
pdx_shapes.each do |k,v|
  x=table k => shapefile(v) do |t|
      t.drop_table
      t.load_shapefile(t.prerequisites.first, :append => false)
  end
  pdx_shape_tasks << x
end

desc "Run all building and address related tasks"
task :all_pdx => [:pdx_bldgs, :pdx_addrs, :taxlots]

desc "load raw building footprints. Used only by :pdx_bldgs tasks"
task :pdx_bldgs_orig do |t|
  t.run %Q{
    UPDATE #{t.name}
      SET the_geom=st_makevalid(the_geom) 
      WHERE not st_isvalid(the_geom);

    ALTER TABLE #{t.name}
      RENAME COLUMN gid to pdx_bldg_id;
  }
  t.add_centroids
end

# join table that has only 1:1 building to taxlot mappings
# by geometry
table  :taxlot_bldgs => [:taxlots, :pdx_bldgs_orig] do |t|
  t.drop_table
  t.run %Q{
    CREATE TABLE #{t.name} AS
    SELECT t.tlid,b.pdx_bldg_id
    FROM pdx_bldgs_orig b
    JOIN taxlots t
      ON ST_Intersects(t.the_geom,b.the_geom_centroids);
  }
  t.run %Q{
    DELETE FROM 
    -- SELECT * FROM
    #{t.name}
      WHERE tlid IN (
        SELECT tlid from #{t.name}
        GROUP by tlid
        HAVING COUNT(*)>1
        );
  }
  t.add_index :tlid
  t.add_index :pdx_bldg_id
  t.add_update_column
end


desc "Generate final format building footprint data"
table :pdx_bldgs => [:pdx_bldgs_orig, :pdx_addrs, :taxlot_bldgs, :taxlot_addrs] do |t|
  t.drop_table
  t.run %Q{
  CREATE table pdx_bldgs as 
    SELECT  b.bldg_id,
    b.pdx_bldg_id,
    NULL::integer as address_id,
    b.num_story as levels,
    round(b.surf_elev::numeric * 0.3048,2) as ele,
    round(b.max_height::numeric * 0.3048,2) as height,
    b.bldg_name as name,
    b.bldg_use,
    0::integer as no_addrs,
    the_geom_centroids,
    st_multi(ST_SimplifyPreserveTopology(b.the_geom,0.000001))::geometry(MultiPolygon,4326) as the_geom
  FROM pdx_bldgs_orig b;
  }

  t.add_spatial_index(:the_geom)
  t.add_spatial_index(:the_geom_centroids)
  t.add_index(:address_id)
  t.add_index(:bldg_id)
  t.add_index(:no_addrs)

  t.run %Q{
  UPDATE #{t.name} bl
    SET no_addrs=addr_count
    FROM (
      SELECT bldg_id,count(*) as addr_count
        FROM pdx_bldgs b
        JOIN pdx_addrs a ON st_intersects(a.the_geom,b.the_geom)
        WHERE bldg_id IS NOT NULL
        GROUP by bldg_id
    ) ad
    WHERE ad.bldg_id=bl.bldg_id;

  UPDATE #{t.name} bl
    SET address_id=a.address_id
    FROM pdx_addrs a
    WHERE st_intersects(bl.the_geom,a.the_geom)
      AND no_addrs=1;

  UPDATE #{t.name} p
    SET address_id=a.address_id, no_addrs=1
    FROM taxlot_bldgs b,taxlot_addrs a
    WHERE p.pdx_bldg_id=b.pdx_bldg_id
    AND b.tlid=a.tlid
    AND p.address_id IS NULL;

  UPDATE #{t.name}
    SET name = btrim(initcap(name))
    WHERE name is not NULL;

  UPDATE #{t.name}
    SET name = NULL
    WHERE name ~* E'^\\d+.* (AVE|ST|PL|CT|PKWY|RD|DR|BLVD|WAY|TER)$'
    OR name ~* E'^\\d+(TH|ST|RD|ND)$'
    OR name ~* '(NE|NW|SW|N) BROADWAY$'
    OR name = 'Unknown'
    OR name ~* ' (AVE|ST)$'
    OR name in ('Glisan', 'Couch', 'Davis',
                'Broadway','Burnside', '321 Ne Davis',
                '930 Wi/Sw Hall Ave (Sports Complex)',
                '320 Sw Washington',
                'Everett','Pine','301 Nw 10th Ave, Ste 200',
                '115 Commerce Park','Hoyt','22nd',
                '115 Ne 102nd Ave, Un 1-12',
                '50 Sw Pine','Ash','Kearney','Lovejoy','Oak'
                '1 Wi/ Center Ct','2025 Wi/ Sw River Pkwy',
                '230 Se Burnside'
                );


  UPDATE #{t.name}
    SET name = CASE
    WHEN name ~* E'(Salmon|Main) St\\.'
      THEN regexp_replace(name, E'\\mSt\\.','Street','i')
    WHEN name ~* E'\\mSt\\.'
      THEN regexp_replace(name, E'\\mSt\\.','Saint','i')
    WHEN name ~* E'\\mBLDG\\.'
      THEN regexp_replace(name, E'\\mBLDG\\.', 'Building','i')
    WHEN name ~* E'\\mBLDG '
      THEN regexp_replace(name, E'\\mBLDG ', 'Building','i')
    WHEN name ~* E'\\mMtn\\.'
      THEN regexp_replace(name, E'\\mMtn\\.', 'Mountain','i')
    WHEN name ~* E'\\mMt\\.'
      THEN regexp_replace(name, E'\\mMt\\.', 'Mount', 'i')
    WHEN name ~* E'\\mCttge'
      THEN regexp_replace(name, E'\\mCttge', 'Cottage', 'i')
    WHEN name ~* E'\\mH\\.S\\.'
      THEN regexp_replace(name, E'\\mH\\.S\\.', 'High School', 'i')
    WHEN name ~* E'^Psu'
      THEN regexp_replace(name, E'^Psu', 'Portland State University', 'i')
    ELSE name
    END 
    WHERE name is not NULL;

  UPDATE #{t.name} 
    SET name = 
    CASE name
    WHEN 'Riverscape Townhomes Building15'
      THEN 'Riverscape Townhomes Building 15'
    WHEN 'George R. White Library And Learning Ctr'
      THEN 'George R. White Library And Learning Center'
    WHEN 'Mc Cormick Pier Condominiums'
      THEN 'McCormick Pier Condominiums'
    WHEN 'At&T Building'
      THEN 'AT&T Building'
    WHEN 'Us Bancorp Tower Parking'
      THEN 'US Bancorp Tower Parking'
    WHEN 'Macy''S & The Nines'
      THEN 'Macy''s & The Nines'
    WHEN 'Ohsu Center For Health And Healing'
      THEN 'OHSU Center For Health And Healing'
    WHEN 'Us Bancorp Tower'
      THEN 'US Bancorp Tower'
    WHEN 'Steens Mtn Building'
      THEN 'Steens Mountain Building'
    WHEN 'Pcc Willow Creek'
      THEN 'PCC Willow Creek'
    WHEN 'Pge Park'
      THEN 'Jeld-Wen Field'
    WHEN 'Us Bank Wilsonville'
      THEN 'US Bank Wilsonville'
    WHEN 'Strawberry Mtn. Bld'
      THEN 'Strawberry Mountain Building'
    WHEN 'Merlo Halll'
      THEN 'Merlo Hall'
    WHEN 'Mckinstry Or Headquarters'
      THEN 'McKinstry Oregon Headquarters'
    WHEN 'Ne Equipment Shed'
      THEN 'Northeast Equipment Shed'
    WHEN 'Nw Station Way'
      THEN 'Northwest Station Way'
    WHEN 'Ods Tower'
      THEN 'ODS Tower'
    WHEN 'Ymca Y''S Choice Child Development Center'
      THEN 'YMCA Y''s Choice Child Development Center'
    WHEN 'First Unitarian Church Salmon Street S'
      THEN 'First Unitarian Church Salmon Street'
    WHEN 'First Unitarian Church Main St. San'
      THEN 'First Unitarian Church Main Street'
    ELSE name
    END
    WHERE name IS NOT NULL;

    UPDATE #{t.name} SET
      bldg_use = NULL
      WHERE name='Storage A'
        AND bldg_use='Commercial Restaurant';

    UPDATE #{t.name}
      SET bldg_use='Institutional Religious'
      WHERE name='First Unitarian Church Parish Hall'
  }

  t.add_update_column
end
