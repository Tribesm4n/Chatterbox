/// @param filename
/// @param nodeTags
/// @param bodyString

function __ChatterboxClassNode(_filename, _node_tags, _body_string) constructor
{
    if (__CHATTERBOX_DEBUG_COMPILER) __ChatterboxTrace("[", _title, "]");
    
    filename         = _filename;
    title            = _node_tags.title;
    tags             = _node_tags;
    root_instruction = new __ChatterboxClassInstruction(undefined, -1, 0);
    
    //Prepare body string for parsing
    var _work_string = _body_string;
    _work_string = string_replace_all(_work_string, "\n\r", "\n");
    _work_string = string_replace_all(_work_string, "\r\n", "\n");
    _work_string = string_replace_all(_work_string, "\r"  , "\n");
    
    //Perform find-replace
    var _i = 0;
    repeat(ds_list_size(global.__chatterboxFindReplaceOldString))
    {
        _work_string = string_replace_all(_work_string,
                                          global.__chatterboxFindReplaceOldString[| _i],
                                          global.__chatterboxFindReplaceNewString[| _i]);
        ++_i;
    }
    
    //Add a trailing newline to make sure we parse correctly
    _work_string += "\n";
    
    var _substring_array = __ChatterboxSplitBody(_work_string);
    __ChatterboxCompile(_substring_array, root_instruction);
    
    static MarkVisited = function()
    {
        var _long_name = "visited(" + string(filename) + CHATTERBOX_FILENAME_SEPARATOR + string(title) + ")";
        
        var _value = CHATTERBOX_VARIABLES_MAP[? _long_name];
        if (_value == undefined)
        {
            CHATTERBOX_VARIABLES_MAP[? _long_name] = 1;
        }
        else
        {
            CHATTERBOX_VARIABLES_MAP[? _long_name]++;
        }
    }
    
    static toString = function()
    {
        return "Node " + string(filename) + CHATTERBOX_FILENAME_SEPARATOR + string(title);
    }
}

/// @param bodyString
function __ChatterboxSplitBody(_body)
{
    var _in_substring_array = [];
    
    var _body_byte_length = string_byte_length(_body);
    var _body_buffer = buffer_create(_body_byte_length+1, buffer_fixed, 1);
    buffer_write(_body_buffer, buffer_string, _body);
    buffer_seek(_body_buffer, buffer_seek_start, 0);
    
    var _line          = 0;
    var _first_on_line = true;
    var _indent        = undefined;
    var _newline       = false;
    var _cache         = "";
    var _cache_type    = "text";
    var _prev_value    = 0;
    var _value         = 0;
    var _next_value    = __ChatterboxReadUTF8Char(_body_buffer);
    var _in_comment    = false;
    var _in_metadata   = false;
    
    repeat(_body_byte_length)
    {
        if (_next_value == 0) break;
        
        _prev_value = _value;
        _value      = _next_value;
        _next_value = __ChatterboxReadUTF8Char(_body_buffer);
        
        var _write_cache = true;
        var _pop_cache   = false;
        
        if ((_value == ord("\n")) || (_value == ord("\r")))
        {
            _newline     = true;
            _pop_cache   = true;
            _write_cache = false;
            _in_comment  = false;
            _in_metadata = false;
        }
        else if (_in_comment)
        {
            _write_cache = false;
        }
        else if (_in_metadata)
        {
            if ((_value == ord("/")) && (_next_value == ord("/")))
            {
                _in_comment  = true;
                _pop_cache   = true;
                _write_cache = false;
            }
            else if (_value == ord("#"))
            {
                _pop_cache   = true;
                _write_cache = false;
            }
        }
        else
        {
            if ((_prev_value != ord("\\")) && (_value == ord("#")))
            {
                _in_metadata = true;
                _pop_cache   = true;
                _write_cache = false;
            }
            else if ((_value == ord("/")) && (_next_value == ord("/")))
            {
                _in_comment  = true;
                _pop_cache   = true;
                _write_cache = false;
            }
            else if (_value == ord(__CHATTERBOX_ACTION_OPEN_DELIMITER))
            {
                if (_next_value == ord(__CHATTERBOX_ACTION_OPEN_DELIMITER))
                {
                    _write_cache = false;
                    _pop_cache   = true;
                }
                else if (_prev_value == ord(__CHATTERBOX_ACTION_OPEN_DELIMITER))
                {
                    _write_cache = false;
                    _cache_type = "command";
                }
            }
            else if (_value == ord(__CHATTERBOX_ACTION_CLOSE_DELIMITER))
            {
                if (_next_value == ord(__CHATTERBOX_ACTION_CLOSE_DELIMITER))
                {
                    _write_cache = false;
                    _pop_cache   = true;
                }
                else if (_prev_value == ord(__CHATTERBOX_ACTION_CLOSE_DELIMITER))
                {
                    _write_cache = false;
                }
            }
        }
        
        if (_write_cache) _cache += chr(_value);
        
        if (_pop_cache)
        {
            if (_first_on_line)
            {
                _cache = __ChatterboxRemoveWhitespace(_cache, true);
                _indent = global.__chatterboxIndentSize;
            }
            else if (_in_metadata)
            {
                _cache = __ChatterboxRemoveWhitespace(_cache, true);
                _indent = 0;
            }
            
            _cache = __ChatterboxRemoveWhitespace(_cache, false);
            
            if (_cache != "") array_push(_in_substring_array, [_cache, _cache_type, _line, _indent]);
            _cache = "";
            _cache_type = _in_metadata? "metadata" : "text";
            
            if (_newline)
            {
                _newline = false;
                ++_line;
                _first_on_line = true;
                _indent = undefined;
            }
            else
            {
                _first_on_line = false;
            }
        }
    }
    
    buffer_delete(_body_buffer);
    
    array_push(_in_substring_array, ["stop", "command", _line, 0]);
    return _in_substring_array;
}

/// @param substringList
/// @param rootInstruction
function __ChatterboxCompile(_in_substring_array, _root_instruction)
{
    if (array_length(_in_substring_array) <= 0) exit;
    
    var _previous_instruction = _root_instruction;
    
    var _if_stack = [];
    var _if_depth = -1;
    
    var _substring_count = array_length(_in_substring_array);
    var _s = 0;
    while(_s < _substring_count)
    {
        var _substring_array = _in_substring_array[_s];
        var _string          = _substring_array[0];
        var _type            = _substring_array[1];
        var _line            = _substring_array[2];
        var _indent          = _substring_array[3];
        
        var _instruction = undefined;
        
        if (__CHATTERBOX_DEBUG_COMPILER) __ChatterboxTrace("ln ", string_format(_line, 4, 0), " ", __ChatterboxGenerateIndent(_indent), _string);
        
        if (string_copy(_string, 1, 2) == "->") //Shortcut //TODO - Make this part of the substring splitting step
        {
            var _instruction = new __ChatterboxClassInstruction("shortcut", _line, _indent);
            _instruction.text = new __ChatterboxClassText(__ChatterboxRemoveWhitespace(string_delete(_string, 1, 2), all));
        }
        else if (_type == "command")
        {
            #region <<command>>
            
            _string = __ChatterboxRemoveWhitespace(_string, true);
            
            var _pos = string_pos(" ", _string);
            if (_pos > 0)
            {
                var _first_word = string_copy(_string, 1, _pos-1);
                var _remainder = string_delete(_string, 1, _pos);
            }
            else
            {
                var _first_word = _string;
                var _remainder = "";
            }
            
            switch(_first_word)
            {
                case "declare":
                    var _instruction = new __ChatterboxClassInstruction(_first_word, _line, _indent);
                    _instruction.expression = __ChatterboxParseExpression(_remainder);
                break;
                
                case "set":
                    var _instruction = new __ChatterboxClassInstruction(_first_word, _line, _indent);
                    _instruction.expression = __ChatterboxParseExpression(_remainder);
                break;
                
                case "jump":
                    var _instruction = new __ChatterboxClassInstruction("jump", _line, _indent);
                    _instruction.destination = __ChatterboxRemoveWhitespace(_remainder, all);
                break;
                
                case "if":
                    if (_previous_instruction.line == _line)
                    {
                        _previous_instruction.condition = __ChatterboxParseExpression(_remainder);
                        //We *don't* make a new instruction for the if-statement, just attach it to the previous instruction as a condition
                    }
                    else
                    {
                        var _instruction = new __ChatterboxClassInstruction("if", _line, _indent);
                        _instruction.condition = __ChatterboxParseExpression(_remainder);
                        _if_depth++;
                        _if_stack[@ _if_depth] = _instruction;
                    }
                break;
                    
                case "else":
                    var _instruction = new __ChatterboxClassInstruction("else", _line, _indent);
                    if (_if_depth < 0)
                    {
                        __ChatterboxError("<<else>> found without matching <<if>>");
                    }
                    else
                    {
                        _if_stack[_if_depth].branch_reject = _instruction;
                        _if_stack[@ _if_depth] = _instruction;
                    }
                break;
                    
                case "else if":
                    if (CHATTERBOX_ERROR_NONSTANDARD_SYNTAX) __ChatterboxError("<<else if>> is non-standard Yarn syntax, please use <<elseif>>\n \n(Set CHATTERBOX_ERROR_NONSTANDARD_SYNTAX to <false> to hide this error)");
                case "elseif":
                    var _instruction = new __ChatterboxClassInstruction("else if", _line, _indent);
                    _instruction.condition = __ChatterboxParseExpression(_remainder);
                    if (_if_depth < 0)
                    {
                        __ChatterboxError("<<else if>> found without matching <<if>>");
                    }
                    else
                    {
                        _if_stack[_if_depth].branch_reject = _instruction;
                        _if_stack[@ _if_depth] = _instruction;
                    }
                break;
                
                case "end if":
                    if (CHATTERBOX_ERROR_NONSTANDARD_SYNTAX) __ChatterboxError("<<end if>> is non-standard Yarn syntax, please use <<endif>>\n \n(Set CHATTERBOX_ERROR_NONSTANDARD_SYNTAX to <false> to hide this error)");
                case "endif":
                    var _instruction = new __ChatterboxClassInstruction("end if", _line, _indent);
                    if (_if_depth < 0)
                    {
                        __ChatterboxError("<<endif>> found without matching <<if>>");
                    }
                    else
                    {
                        _if_stack[_if_depth].branch_reject = _instruction;
                        _if_depth--;
                    }
                break;
                
                case "wait":
                case "stop":
                    _remainder = __ChatterboxRemoveWhitespace(_remainder, true);
                    if (_remainder != "")
                    {
                        __ChatterboxError("Cannot use arguments with <<wait>> or <<stop>>\n\Action was \"<<", _string, ">>\"");
                    }
                    else
                    {
                        var _instruction = new __ChatterboxClassInstruction(_first_word, _line, _indent);
                    }
                break;
                    
                default:
                    var _instruction = new __ChatterboxClassInstruction("direction", _line, _indent);
                    _instruction.text = new __ChatterboxClassText(_string);
                break;
            }
            
            #endregion
        }
        else if (_type == "metadata")
        {
            #region #metadata
            
            if (_previous_instruction != undefined)
            {
                if (_previous_instruction.type != "content")
                {
                    __ChatterboxTrace("Warning! Previous instruction wasn't content, metadata \"\#", _string, "\" cannot be applied");
                }
                else if (_previous_instruction.line != _line)
                {
                    __ChatterboxTrace("Warning! Previous instruction (ln ", _previous_instruction.line, ") was a different line to metadata (ln ", _line, "), \"\#", _string, "\"");
                }
                else
                {
                    array_push(_previous_instruction.metadata, _string)
                }
            }
            
            #endregion
        }
        else if (_type == "text")
        {
            var _instruction = new __ChatterboxClassInstruction("content", _line, _indent);
            _instruction.text = new __ChatterboxClassText(_string);
        }
        
        if (_instruction != undefined)
        {
            __ChatterboxInstructionAdd(_previous_instruction, _instruction);
            _previous_instruction = _instruction;
        }
        
        ++_s;
    }
}



/// @param string
/// @param allowActionSyntax
function __ChatterboxParseExpression(_string)
{
    enum __CHATTERBOX_TOKEN
    {
        NULL       = -1,
        UNKNOWN    =  0,
        IDENTIFIER =  1,
        STRING     =  2,
        NUMBER     =  3,
        SYMBOL     =  4,
    }
    
    var _tokens = [];
    
    var _buffer = buffer_create(string_byte_length(_string)+1, buffer_fixed, 1);
    buffer_write(_buffer, buffer_string, _string);
    
    var _read_start   = 0;
    var _state        = __CHATTERBOX_TOKEN.UNKNOWN;
    var _next_state   = __CHATTERBOX_TOKEN.UNKNOWN;
    var _last_byte    = 0;
    var _new          = false;
    var _change_state = true;
    
    var _b = 0;
    repeat(buffer_get_size(_buffer))
    {
        var _byte = buffer_peek(_buffer, _b, buffer_u8);
        _next_state = (_byte == 0)? __CHATTERBOX_TOKEN.NULL : __CHATTERBOX_TOKEN.UNKNOWN;
        _change_state = true;
        _new = false;
        
        switch(_state)
        {
            case __CHATTERBOX_TOKEN.IDENTIFIER: //Identifier (variable/function)
                #region
                
                //Everything is permitted, except whitespace and a dollar sign
                if ((_byte > 32) && (_byte != ord("$")))
                {
                    _next_state = __CHATTERBOX_TOKEN.IDENTIFIER;
                }
                
                if ((_state != _next_state) || (_last_byte == ord("("))) //Cheeky hack to find functions
                {
                    var _is_symbol   = false;
                    var _is_number   = false;
                    var _is_function = (_last_byte == ord("(")); //Cheeky hack to find functions
                    
                    //Just a normal keyboard/variable
                    buffer_poke(_buffer, _b, buffer_u8, 0);
                    buffer_seek(_buffer, buffer_seek_start, _read_start);
                    var _read = buffer_read(_buffer, buffer_string);
                    buffer_poke(_buffer, _b, buffer_u8, _byte);
                    
                    if (!_is_function)
                    {
                        //Convert friendly human-readable operators into symbolic operators
                        //Also handle numeric keywords too
                        switch(_read)
                        {
                            case "and":       _read = "&&";      _is_symbol = true; break;
                            case "le" :       _read = "<";       _is_symbol = true; break;
                            case "gt" :       _read = ">";       _is_symbol = true; break;
                            case "or" :       _read = "||";      _is_symbol = true; break;
                            case "leq":       _read = "<=";      _is_symbol = true; break;
                            case "geq":       _read = ">=";      _is_symbol = true; break;
                            case "eq" :       _read = "==";      _is_symbol = true; break;
                            case "is" :       _read = "==";      _is_symbol = true; break;
                            case "neq":       _read = "!=";      _is_symbol = true; break;
                            case "to" :       _read = "=";       _is_symbol = true; break;
                            case "not":       _read = "!";       _is_symbol = true; break;
                            case "true":      _read = true;      _is_number = true; break;
                            case "false":     _read = false;     _is_number = true; break;
                            case "undefined": _read = undefined; _is_number = true; break;
                            case "null":      _read = undefined; _is_number = true; break;
                        }
                    }
                    
                    if (_is_symbol)
                    {
                        array_push(_tokens, { op : _read });
                    }
                    else if (_is_number)
                    {
                        array_push(_tokens, _read);
                    }
                    else if (_is_function)
                    {
                        _read = string_copy(_read, 1, string_length(_read)-1); //Trim off the open bracket
                        array_push(_tokens, { op : "func", name : _read });
                    }
                    else
                    {
                        //Parse this variable and figure out what scope we're in
                        var _scope = CHATTERBOX_NAKED_VARIABLE_SCOPE;
                        
                        if (string_char_at(_read, 1) == "$")
                        {
                            _scope = CHATTERBOX_DOLLAR_VARIABLE_SCOPE;
                            _read = string_delete(_read, 1, 1);
                        }
                        else if (string_copy(_read, 1, 2) == "g.")
                        {
                            _scope = "global";
                            _read = string_delete(_read, 1, 2);
                        }
                        else if (string_copy(_read, 1, 7) == "global.")
                        {
                            _scope = "global";
                            _read = string_delete(_read, 1, 7);
                        }
                        else if (string_copy(_read, 1, 2) == "l.")
                        {
                            _scope = "local";
                            _read = string_delete(_read, 1, 2);
                        }
                        else if (string_copy(_read, 1, 6) == "local.")
                        {
                            _scope = "local";
                            _read = string_delete(_read, 1, 6);
                        }
                        else if (string_copy(_read, 1, 2) == "y.")
                        {
                            _scope = "yarn";
                            _read = string_delete(_read, 1, 2);
                        }
                        else if (string_copy(_read, 1, 9) == "yarn.")
                        {
                            _scope = "yarn";
                            _read = string_delete(_read, 1, 9);
                        }
                        
                        if (_scope == "string")
                        {
                            array_push(_tokens, _read);
                        }
                        else
                        {
                            array_push(_tokens, { op : "var", scope : _scope, name : _read });
                        }
                    }
                    
                    _new = true;
                    _next_state = __CHATTERBOX_TOKEN.UNKNOWN;
                }
                
                #endregion
            break;
            
            case __CHATTERBOX_TOKEN.STRING: //Quote-delimited String
                #region
                
                if ((_byte == 0) || ((_byte == 34) && (_last_byte != 92))) //null "
                {
                    _change_state = false;
                    
                    if (_read_start < _b - 1)
                    {
                        buffer_poke(_buffer, _b, buffer_u8, 0);
                        buffer_seek(_buffer, buffer_seek_start, _read_start+1);
                        var _read = buffer_read(_buffer, buffer_string);
                        buffer_poke(_buffer, _b, buffer_u8, _byte);
                    }
                    else
                    {
                        var _read = "";
                    }
                    
                    if (CHATTERBOX_ESCAPE_EXPRESSION_STRINGS) _read = __ChatterboxUnescapeString(_read);
                    
                    array_push(_tokens, _read);
                    _new = true;
                }
                else
                {
                    _next_state = __CHATTERBOX_TOKEN.STRING; //Quote-delimited String
                }
                
                #endregion
            break;
            
            case __CHATTERBOX_TOKEN.NUMBER: //Number
                #region
                
                if (_byte == 46) //.
                {
                    _next_state = __CHATTERBOX_TOKEN.NUMBER;
                }
                else if ((_byte >= 48) && (_byte <= 57)) //0 1 2 3 4 5 6 7 8 9
                {
                    _next_state = __CHATTERBOX_TOKEN.NUMBER;
                }
                
                if (_state != _next_state)
                {
                    buffer_poke(_buffer, _b, buffer_u8, 0);
                    buffer_seek(_buffer, buffer_seek_start, _read_start);
                    var _read = buffer_read(_buffer, buffer_string);
                    buffer_poke(_buffer, _b, buffer_u8, _byte);
                    
                    try
                    {
                        _read = real(_read);
                    }
                    catch(_error)
                    {
                        __ChatterboxError("Error whilst converting expression value to real\n \n(", _error, ")");
                        return undefined;
                    }
                    
                    array_push(_tokens, _read);
                    
                    _new = true;
                }
                
                #endregion
            break;
            
            case __CHATTERBOX_TOKEN.SYMBOL: //Symbol
                #region
                
                if (_byte == 61) //=
                {
                    if ((_last_byte == 33)  // !=
                    ||  (_last_byte == 42)  // *=
                    ||  (_last_byte == 43)  // +=
                    ||  (_last_byte == 45)  // +=
                    ||  (_last_byte == 47)  // /=
                    ||  (_last_byte == 60)  // <=
                    ||  (_last_byte == 61)  // ==
                    ||  (_last_byte == 62)) // >=
                    {
                        _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
                    }
                }
                else if ((_byte == 38) && (_last_byte == 38)) //&
                {
                    _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
                }
                else if ((_byte == 124) && (_last_byte == 124)) //|
                {
                    _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
                }
                
                if (_state != _next_state)
                {
                    buffer_poke(_buffer, _b, buffer_u8, 0);
                    buffer_seek(_buffer, buffer_seek_start, _read_start);
                    var _read = buffer_read(_buffer, buffer_string);
                    buffer_poke(_buffer, _b, buffer_u8, _byte);
                    
                    array_push(_tokens, { op : _read });
                    
                    _new = true;
                }
                
                #endregion
            break;
        }
        
        if (_change_state && (_next_state == __CHATTERBOX_TOKEN.UNKNOWN))
        {
            #region
            
            //TODO - Compress this down
            if (_byte == 33) //!
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if ((_byte == 34) && (_last_byte != 92)) //"
            {
                _next_state = __CHATTERBOX_TOKEN.STRING; //Quote-delimited String
            }
            else if (_byte == 36) //$
            {
                _next_state = __CHATTERBOX_TOKEN.IDENTIFIER; //Word/Variable Name
            }
            else if ((_byte == 37) || (_byte == 38)) //% &
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if ((_byte == 40) || (_byte == 41)) //( )
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if ((_byte == 42) || (_byte == 43)) //* +
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if (_byte == 44) //,
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if (_byte == 45) //-
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if (_byte == 46) //.
            {
                _next_state = __CHATTERBOX_TOKEN.NUMBER; //Number
            }
            else if (_byte == 47) // /
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if ((_byte >= 48) && (_byte <= 57)) //0 1 2 3 4 5 6 7 8 9
            {
                _next_state = __CHATTERBOX_TOKEN.NUMBER; //Number
            }
            else if ((_byte == 60) || (_byte == 61) || (_byte == 62)) //< = >
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            else if ((_byte >= 65) && (_byte <= 90)) //a b c...x y z
            {
                _next_state = __CHATTERBOX_TOKEN.IDENTIFIER; //Word/Variable Name
            }
            else if (_byte == 95) //_
            {
                _next_state = __CHATTERBOX_TOKEN.IDENTIFIER; //Word/Variable Name
            }
            else if ((_byte >= 97) && (_byte <= 122)) //A B C...X Y Z
            {
                _next_state = __CHATTERBOX_TOKEN.IDENTIFIER; //Word/Variable Name
            }
            else if (_byte == 124) // |
            {
                _next_state = __CHATTERBOX_TOKEN.SYMBOL; //Symbol
            }
            
            #endregion
        }
        
        if (_new || (_state != _next_state)) _read_start = _b;
        _state = _next_state;
        if (_state == __CHATTERBOX_TOKEN.NULL) break;
        _last_byte = _byte;
        
        ++_b;
    }
    
    buffer_delete(_buffer);
    
    __ChatterboxCompileExpression(_tokens);
    
    if (array_length(_tokens) > 1)
    {
        __ChatterboxError("Expression could not be fully resolved into a single token (", _string, ")");
    }
    else if (array_length(_tokens) < 1)
    {
        __ChatterboxError("No valid expression tokens found (", _string, ")");
    }
    else
    {
        return _tokens[0];
    }
}



/// @param array
/// @param startIndex
/// @param endIndex
function __ChatterboxCompileExpression(_source_array)
{
    //Handle parentheses
    var _depth = 0;
    var _open = undefined;
    var _sub_expression_start = undefined;
    var _is_function = false;
    var _t = 0;
    while(_t < array_length(_source_array))
    {
        var _token = _source_array[_t];
        if (is_struct(_token))
        {
            if ((_token.op == "(") || (_token.op == "func"))
            {
                ++_depth;
                if (_depth == 1)
                {
                    if (_token.op == "func")
                    {
                        _is_function = true;
                        _open = _t + 1;
                    }
                    else
                    {
                        _open = _t;
                        _is_function = false;
                        array_delete(_source_array, _open, 1);
                        --_t;
                    }
                    
                    _sub_expression_start = _open;
                }
            }
            else if (_token.op == ",")
            {
                if (_depth == 1)
                {
                    var _sub_array = __ChatterboxArrayCopyPart(_source_array, _sub_expression_start, _t - _sub_expression_start);
                    array_delete(_source_array, _sub_expression_start, array_length(_sub_array));
                    __ChatterboxCompileExpression(_sub_array);
                    
                    _source_array[@ _sub_expression_start] = { op : "param", a : _sub_array[0] };
                    
                    _t = _sub_expression_start;
                    ++_sub_expression_start;
                }
            }
            else if (_token.op == ")")
            {
                --_depth;
                if (_depth == 0)
                {
                    var _sub_array = __ChatterboxArrayCopyPart(_source_array, _sub_expression_start, _t - _sub_expression_start);
                    array_delete(_source_array, _sub_expression_start, array_length(_sub_array));
                    __ChatterboxCompileExpression(_sub_array);
                    
                    _source_array[@ _sub_expression_start] = { op : "paren", a : _sub_array[0] };
                    
                    if (_is_function)
                    {
                        var _parameters = __ChatterboxArrayCopyPart(_source_array, _open, 1 + _sub_expression_start - _open);
                        array_delete(_source_array, _open, 1 + _sub_expression_start - _open);
                        
                        _source_array[_open - 1].parameters = _parameters;
                        _t = _open - 1;
                    }
                    else
                    {
                        _t = _open;
                    }
                }
            }
        }
        
        ++_t;
    }
    
    //Scan for negation (! / NOT)
    var _t = 0;
    while(_t < array_length(_source_array))
    {
        var _token = _source_array[_t];
        if (is_struct(_token))
        {
            if (_token.op == "!")
            {
                _token.a = _source_array[_t+1];
                array_delete(_source_array, _t+1, 1);
            }
        }
        
        ++_t;
    }
    
    //Scan for negative signs
    var _t = 0;
    while(_t < array_length(_source_array))
    {
        var _token = _source_array[_t];
        if (is_struct(_token))
        {
            if (_token.op == "-")
            {
                //If this token was preceded by a symbol (or nothing) then it's a negative sign
                if ((_t == 0) || (__chatterboxStringIsSymbol(_source_array[_t-1], true)))
                {
                    _token.op = "neg";
                    _token.a = _source_array[_t+1];
                    array_delete(_source_array, _t+1, 1);
                }
            }
        }
        
        ++_t;
    }
    
    var _o = 0;
    repeat(ds_list_size(global.__chatterboxOpList))
    {
        var _operator = global.__chatterboxOpList[| _o];
        
        var _t = 0;
        while(_t < array_length(_source_array))
        {
            var _token = _source_array[_t];
            if (is_struct(_token))
            {
                if (_token.op == _operator)
                {
                    _token.a = _source_array[_t-1];
                    _token.b = _source_array[_t+1];
                    
                    //Order of operation very important here!
                    array_delete(_source_array, _t+1, 1);
                    array_delete(_source_array, _t-1, 1);
                    
                    //Correct for token deletion
                    --_t;
                }
            }
            
            ++_t;
        }
        
        ++_o;
    }
    
    return _source_array;
}



/// @param string
/// @param ignoreCloseParentheses
function __chatterboxStringIsSymbol(_string, _ignore_close_paren)
{
    if ((_string == "(" )
    || ((_string == ")" ) && !_ignore_close_paren)
    ||  (_string == "!" )
    ||  (_string == "/=")
    ||  (_string == "/" )
    ||  (_string == "*=")
    ||  (_string == "*" )
    ||  (_string == "+" )
    ||  (_string == "+=")
    ||  (_string == "-" )
    ||  (_string == "-=")
    ||  (_string == "||")
    ||  (_string == "&&")
    ||  (_string == ">=")
    ||  (_string == "<=")
    ||  (_string == ">" )
    ||  (_string == "<" )
    ||  (_string == "!=")
    ||  (_string == "==")
    ||  (_string == "=" ))
    {
        return true;
    }
    
    return false;
}