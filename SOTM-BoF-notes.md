* Revise building tagging strategy -- anything vague from land use info (church, industrial, etc.) should probably be just building = yes.
* Keep an eye out for weird edge cases in code
* Convert, split into chunks, upload after checking each chunk at a time
* First run, attach address to building (only works for buildings with only one address)
* Second phase: dealing with multiple addresses spread over multiple buildings. Import the buildings wihtout the addresses in the meantime?
* Or upload address points around (spread out enough), go in person and drag them to the right spot on a mobile phone
* One address per building, tag the building. Multiple, put the nodes around in the right place. Don't need to create relations.
* Human mappers can make errors as well
* Get the data in as fast as possible, then work on improving it with the community. Improving and adding to it is a lot more fun for new and community members.
* Maproulette style? Or just split
* OSM FR has scripts to check for and fix small building overlaps/missing and duplicate addresses
* Flag/query buildings that exist in OSM and don't have addresses, add addresses to these
* Skip the addr:country tag
* Generate some .osm files for the imports-us committee to look at
* Defer till after the data update in May
