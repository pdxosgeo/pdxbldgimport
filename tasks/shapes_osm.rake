desc "Load quarter section shapefile"
table :qtr_sec  =>  [shapefile("qtr_sec/qtr_sec.shp")] do |t|
  # t.drop_table?
  t.load_shapefile(t.prerequisites.first, :append => false)

  t.run %Q{
    ALTER TABLE #{t.name} 
      ADD COLUMN bldg_count integer;

    UPDATE #{t.name}
    SET bldg_count = a.count
    FROM (SELECT count(1),q.qtrsec 
          FROM qtr_sec q 
          JOIN pdx_bldgs b ON (st_intersects(q.the_geom,b.the_geom_centroids))
          GROUP BY q.qtrsec) a
    WHERE a.qtrsec=#{t.name}.qtrsec;

    DELETE FROM
      #{t.name} WHERE bldg_count IS NULL;
    
  }
  t.add_update_column
end

table :conslidated_qtr_secs => [:qtr_sec] do |t|
  t.drop_table

  t.run %Q{
    CREATE TABLE #{t.name} (
      qs_id serial primary key,
      qtrsec text,
      the_geom geometry(MultiPolygon,4326)
    );
  }
  t.add_spatial_index :the_geom
  t.add_update_column
  t.run %Q{
    INSERT INTO #{t.name}(qtrsec,the_geom)
    SELECT qtrsec,st_multi(the_geom) as the_geom
    FROM qtr_sec
    WHERE bldg_count>=500;
  }

  qs=DB[:qtr_sec].where{bldg_count < 500}.order_by(:qtr_sec).all 

  current_count=0
  to_consolidate=[]
  i=0
  until qs.empty? do
    to_consolidate[i]||=[]
    while current_count < 500 and not qs.empty? do
      q=qs.pop
      next if q.nil?
      current_count+=q[:bldg_count]
      to_consolidate[i].push(q[:qtrsec])
    end
    i+=1
    current_count=0
  end

  to_consolidate.each do |qs|
    q=qs.map{|x| %Q{'#{x}'}}
    t.run %Q{
      INSERT INTO #{t.name}(qtrsec,the_geom)
      SELECT '#{qs.first}'::text,st_multi(ST_UNION(the_geom)) as the_geom
      FROM qtr_sec
      WHERE qtrsec in (#{q.join(',')})
    }
  end
end

if DB.tables.include?(:conslidated_qtr_secs)

  @qtr_secs=DB[:conslidated_qtr_secs].map(:qtrsec).uniq

  @qtr_secs.each do |qtrsec|
    file "shps/#{qtrsec}.shp" do
      sh %Q{ogr2ogr -f "ESRI Shapefile" shps/#{qtrsec}.shp PG:"" \
      -sql "SELECT state_id,
              bldg_id,
              pdx_bldg_id as pdx_bldg_i,
              address_id,
              housenumber as housenum,
              street,
              postcode,
              city,
              state,
              country,
              levels,
              ele,
              height,
              name,
              bldg_type,
              no_addrs,
              the_geom,
              qtrsec 
              FROM pdx_bldgs WHERE qtrsec='#{qtrsec}'"
          }
    end

    file "shps/#{qtrsec}.osm" => "shps/#{qtrsec}.shp" do
      sh %Q{python #{__dir__}/../../ogr2osm/ogr2osm.py "shps/#{qtrsec}.shp" \
      -o shps/#{qtrsec}.osm \
      -t #{__dir__}/../scripts/pdx_bldg_translate.py}
    end
  end  
end

desc "Generate all OSM file chunks"
task :all_osm_files do |t|
  Rake::Task.tasks.each do |task|
    task.invoke if task.name =~ /^shps\/.*osm/
  end
end

