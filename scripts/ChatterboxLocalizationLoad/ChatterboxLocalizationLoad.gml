/// @param path

function ChatterboxLocalizationLoad(_path)
{
    var _grid = load_csv(_path); //TODO - Replace with SNAP?
    
    var _filename = "????";
    var _node     = "????";
    var _prefix   = "????:????:";
    
    var _y = 1;
    repeat(ds_grid_height(_grid)-1)
    {
        if (_grid[# 0, _y] != "")
        {
            _filename = _grid[# 0, _y];
            _node     = "????";
            _prefix   = _filename + ":" + _node + ":";
        }
        
        if (_grid[# 1, _y] != "")
        {
            _node   = _grid[# 1, _y];
            _prefix = _filename + ":" + _node + ":";
        }
        
        var _hash = _grid[# 2, _y];
        var _text = _grid[# 3, _y];
        
        if ((_hash != "") && (_text != ""))
        {
            global.__chatterboxLocalisationMap[? _prefix + _hash] = _text;
        }
        
        ++_y;
    }
    
    ds_grid_destroy(_grid);
}