desc "Load quarter section shapefile"
table :qtr_sec  =>  [shapefile("qtr_sec/qtr_sec.shp"), :metro_bldgs, :clark_qtr_sec] do |t|
	t.drop_table?
	t.load_shapefile(t.prerequisites.first, :append => false)

	t.run %Q{
		ALTER TABLE #{t.name} 
			ADD COLUMN bldg_count integer;
	}

	# add washington qtrsecs
	t.run %Q{
		INSERT INTO #{t.name} (qtrsec, the_geom)
			SELECT quarter::text,the_geom
			FROM clark_qtr_sec;
	 }
	 
	 # update the count of actual un-uploaded buildings in each qtr_sec
	 t.run %Q{
		UPDATE #{t.name}
		SET bldg_count = coalesce(a.count,0)
		FROM (SELECT count(1),q.qtrsec 
					FROM qtr_sec q 
					JOIN metro_bldgs b ON (st_intersects(q.the_geom,b.the_geom_centroids))
					GROUP BY q.qtrsec) a
		WHERE a.qtrsec=#{t.name}.qtrsec;
	}
	# delete anything that's empty
	# t.run %Q{
	# 	DELETE FROM
	# 		#{t.name} WHERE bldg_count IS NULL or bldg_count=0;
	# }
	t.add_update_column
end

#table :consolidated_qtr_secs => [:qtr_sec] do |t|
table :consolidated_qtr_secs => [:metro_bldgs, :qtr_sec] do |t|
	t.run %Q{
		UPDATE #{t.name} set updated_at = now();
	}
end

table :consolidated_qtr_secs2 => [:metro_bldgs, :qtr_sec] do |t|
	max_bldgs=50
	t.drop_table

	t.run %Q{
		CREATE TABLE #{t.name} (
			qs_id serial primary key,
			qtrsec text,
			contains text[],
			the_geom geometry(MultiPolygon,4326)
		);
	}
	t.add_update_column
	t.add_spatial_index :the_geom
	
	# first just add each quarter sec that has enough buildings
	t.run %Q{
		INSERT INTO #{t.name}(qtrsec,contains,the_geom)
		SELECT qtrsec,ARRAY[qtrsec],st_multi(the_geom) as the_geom
		FROM qtr_sec
		WHERE bldg_count>=#{max_bldgs};
	}

	# now we consolidate the remaining qtr secs
	# maybe would be nice to guarantee contiguous sections?
	qs=DB["SELECT * FROM qtr_sec where bldg_count<#{max_bldgs} AND bldg_count>=1
			and qtrsec NOT IN (SELECT unnest(contains) from consolidated_qtr_secs)
			AND qtrsec='3s2e30d'"].all
	current_count=0
	until qs.empty? do
		to_consolidate=[]
		q=qs.pop
		current_count+=q[:bldg_count]
		to_consolidate.push(q[:qtrsec])

		while current_count <= max_bldgs do
			candidates=DB["SELECT q2.qtrsec,q2.bldg_count,
				st_distance(st_centroid(q1.the_geom),st_centroid(q2.the_geom)) FROM qtr_sec q1, qtr_sec q2
				where q2.bldg_count<#{max_bldgs}
				and q1.qtrsec=?
				AND q2.qtrsec<>?
				and q2.qtrsec NOT IN (SELECT unnest(contains) from consolidated_qtr_secs)
					ORDER BY 3", q[:qtrsec], q[:qtrsec]].all

				current_count = max_bldgs if candidates.empty?
				puts to_consolidate
				candidates.each do |x|
					next if current_count > max_bldgs
					current_count+=x[:bldg_count]
					to_consolidate.push(x[:qtrsec])
				end
			end # while

			to_consolidate.map!{|x| %Q{'#{x}'}}
			t.run %Q{
				INSERT INTO #{t.name}(qtrsec,contains,the_geom)
				SELECT #{to_consolidate.first}::text,array_agg(qtrsec),st_multi(ST_UNION(the_geom)) as the_geom
				FROM qtr_sec
				WHERE qtrsec in (#{to_consolidate.join(',')})
			}
			qs=DB["SELECT * FROM qtr_sec where bldg_count<#{max_bldgs} and bldg_count>0
							and qtrsec NOT IN (SELECT unnest(contains) from consolidated_qtr_secs)"].all
		current_count=0
	end
end
