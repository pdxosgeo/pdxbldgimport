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

    if 'housenum' in attrs:
        tags.update({'addr:housenumber':attrs['housenum'].strip(' ')})

    if 'street' in attrs:
        tags.update({'addr:street':attrs['street'].strip(' ')})

    if 'postcode' in attrs:
        tags.update({'addr:postcode': attrs['postcode'].strip(' ')})

    if 'city' in attrs:
        tags.update({'addr:city': attrs['city'].strip(' ')})

    if 'levels' in attrs:
        tags.update({'building:levels': attrs['levels']})

    if 'bldg_type' in attrs:
        tags.update({'building': attrs['bldg_type'].strip(' ')}) 

    if 'ele' in attrs:
        if not attrs['ele']=='':
            tags.update({'ele': '%s' % round(float(attrs['ele']), 2)})

    if 'height' in attrs:
        if not attrs['height']=='':
            tags.update({'height': '%s' % round(float(attrs['height']), 2)})

    return tags

