The Configuration module is used for "batch" scripts

Configuration.DoText ( "*" | "^" | textfile { textfile } "~" )
	Execute the commands in textfile . Each command must be written on a separate line.

Configuration.DoCommands ( "^" | cmd { cmd } "~" )
	Execute the commands. Each command must be written on a separate line.

Configuration.Marker set save		set at saved position
Configuration.Marker set this		set to current viewer
Configuration.Marker set system		in system track
Configuration.Marker set user		in user track
Configuration.Marker set X Y		at absolute pixel position X, Y
Configuration.Marker set X% Y%		at relative pixel position X, Y
Configuration.Marker save system		save marker in system track
Configuration.Marker save user		save marker in user track
	Set the star marker under program control
