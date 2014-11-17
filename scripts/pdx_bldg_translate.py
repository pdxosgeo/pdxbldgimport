#
# Run like this, from the ogr2osm directory:
# python ogr2osm.py ~/pdxbldgimport/pdx_bldgs_export.shp \
#    -o ~/pdxbldgimport/pdx_bldgs_export.osm \
#    -t ~/pdxbldgimport/scripts/pdx_bldg_translate.py
# 

"""
Translation rules for the PDX Building import

"""

def filterTags(attrs):
    if not attrs: return

    tags = {}
    
    # if attrs['BLDG_ID']:
    #     tags.update({'pdxbldgs:id':attrs['BLDG_ID'].strip(' ')})

    if attrs['housenum']:
        tags.update({'addr:housenumber':attrs['housenum'].strip(' ')})

    if attrs['street']:
        tags.update({'addr:street':attrs['street'].strip(' ')})

    if attrs['postcode']:
        tags.update({'addr:postcode': attrs['postcode'].strip(' ')})

    if attrs['city']:
        tags.update({'addr:city': attrs['city'].strip(' ')})

    if attrs['levels']:
        tags.update({'building:levels': attrs['levels']})

    if attrs['bldg_type']:
        tags.update({'building': attrs['bldg_type'].strip(' ')}) 

    if attrs['ele']: 
        tags.update({'ele': '%s' % round(float(attrs['ele']), 2)})

    if attrs['height']: 
        tags.update({'height': '%s' % round(float(attrs['height']), 2)})

    return tags

