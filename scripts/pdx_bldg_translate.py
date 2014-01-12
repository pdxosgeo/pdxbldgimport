"""
Translation rules for the PDX Building import

"""

def filterTags(attrs):
    if not attrs: return

    tags = {}
    
    if attrs['BLDG_ID']:
        tags.update({'pdxbldgs:id':attrs['BLDG_ID'].strip(' ')})

    if attrs['HOUSENUMBE']:
        tags.update({'addr:housenumber':attrs['HOUSENUMBE'].strip(' ')})

    if attrs['STREET']:
        tags.update({'addr:street':attrs['STREET'].strip(' ')})

    if attrs['POSTCODE']:
        tags.update({'addr:postcode': attrs['POSTCODE'].strip(' ')})

    if attrs['CITY']:
        tags.update({'addr:city': attrs['CITY'].strip(' ')})

    if attrs['COUNTRY']:
        tags.update({'addr:country': attrs['COUNTRY'].strip(' ')})

    if attrs['STATE']:
        tags.update({'addr:state': attrs['STATE'].strip(' ')})  

    if attrs['LEVELS']:
        tags.update({'building:levels': attrs['LEVELS']})

    if attrs['BUILDING']:
        tags.update({'building': attrs['BUILDING'].strip(' ')}) 

    if attrs['ELE'] and isinstance(attrs['ELE'], float):
        tags.update({'ele': round(attrs['ELE'], 2)})

    if attrs['HEIGHT'] and isinstance(attrs['HEIGHT'], float):
        height = 0
        height = round(attrs['HEIGHT'], 2)
        if height == 0.00:
            pass
        else:
            tags.update({'height': attrs['HEIGHT']}) 

    if attrs['NAME']:
        tags.update({'name': attrs['NAME'].strip(' ').title()})
        #TODO: also expand St. to Saint, anything else? 

    return tags

