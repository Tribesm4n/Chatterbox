/// Adds a Yarn .json file definition to Chatterbox. This file is loaded and parsed in chatterbox_init_end().
///
/// To find out more about Chatterbox's scripting language, "Yarn", please read the __chatterbox_syntax().
///
/// @param fileName  Name of the Yarn .json file to add
function chatterbox_init_add_json(argument0) {

	if ( !variable_global_exists("__chatterbox_init_complete") )
	{
	    __chatterbox_error("chatterbox_init_add() should be called after chatterbox_init_start()");
	    return undefined;
	}

	if (global.__chatterbox_init_complete)
	{
	    __chatterbox_error("chatterbox_init_add() should be called before chatterbox_init_end()");
	    return undefined;
	}

	var _file = argument0;

	if (ds_map_exists(global.__chatterbox_file_data, _file))
	{
	    __chatterbox_error("\"" + _file + "\" has already been added");
	    return undefined;
	}

	if (!is_string(_file))
	{
	    __chatterbox_error("Source files should be initialised using their filename as a string.\n(Input was an invalid datatype)");
	    return undefined;
	}

	if (global.__chatterbox_default_file == "") global.__chatterbox_default_file = _file;

	var _data = array_create(__CHATTERBOX_FILE.__SIZE);
	global.__chatterbox_file_data[? _file ] = _data;
	_data[@ __CHATTERBOX_FILE.FILENAME] = _file;
	_data[@ __CHATTERBOX_FILE.NAME    ] = _file;
	_data[@ __CHATTERBOX_FILE.FORMAT  ] = __CHATTERBOX_FORMAT.JSON;

	__chatterbox_trace("Added \"" + _file + "\" as a source file");


}
