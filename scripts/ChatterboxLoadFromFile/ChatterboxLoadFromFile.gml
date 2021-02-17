/// Loads a Yarn file (either .yarn or .json) for use with Chatterbox
///
/// To find out more about Chatterbox's scripting language, "Yarn", please read the __chatterbox_syntax()
///
/// @param filename  Name of the file to add
/// @param [aliasName] Alias for the filename

function ChatterboxLoadFromFile()
{
    var _filename  = argument[0];
    var _aliasName = ((argument_count > 1) && (argument[1] != undefined))? argument[1] : undefined;
    
    if (!is_string(_filename))
    {
        __ChatterboxError("Files should be loaded using their filename as a string.\n(Input was an invalid datatype)");
        return undefined;
    }
	
	if (_aliasName != undefined && !is_string(_aliasName))
	{
		__ChatterboxError("Aliases for filenames should be a string.\n(Input was an invalid datatype)");
		return undefined;
	}
    
    //Fix the font directory name if it's weird
    var _font_directory = CHATTERBOX_SOURCE_DIRECTORY;
    var _char = string_char_at(_font_directory , string_length(_font_directory ));
    if (_char != "\\") && (_char != "/") _font_directory += "\\";
    if (!file_exists(_font_directory + _filename))
    {
        __ChatterboxError("\"", _filename, "\" could not be found");
        return undefined;
    }
    
    if (os_browser == browser_not_a_browser)
    {
        var _buffer = buffer_load(_font_directory + _filename);
		if (_aliasName != undefined)
		{
			return ChatterboxLoadFromBuffer(_aliasName, _buffer);
		}
		else
		{
			return ChatterboxLoadFromBuffer(_filename, _buffer);
		}
    }
    else
    {
        __ChatterboxTrace("Using legacy file loading method on HTML5");
        
        var _file = file_text_open_read(_font_directory + _filename);
        var _string = "";
        while(!file_text_eof(_file)) _string += file_text_readln(_file);
        file_text_close(_file);
        
		if (_aliasName != undefined)
		{
			return ChatterboxLoadFromString(_aliasName, _string);
		}
		else
		{
			return ChatterboxLoadFromString(_filename, _string);
		}
    }
}