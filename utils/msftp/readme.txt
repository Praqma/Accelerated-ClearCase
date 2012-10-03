Create a hyperlink type called SpecialTransport. 
In an UCM enviroment create it shared and global on the PVOB

cleartool mkhltype -global -shared -c "Used for non-default replication" SpecialTransport@\PVOB



cleartool mkhlink -unidir -ttext "fpt til her" CTrans replica:CCMSFTP@\enbase replica:nightwalker@\enbase

