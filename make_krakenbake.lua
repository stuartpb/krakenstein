krakenbake=assert(io.open("krakenbake.wlua","r")):read'*a'

embed=io.open("embedded_krakenbake.wlua","w")
embed:write"local function embedded(exe_message)\n"
embed:write(krakenbake,'\n')
embed:write[=[end
external, message = loadfile "krakenbake.wlua"
if external then return external()
else return embedded(message) end
]=]
embed:close()

os.execute"glue empty_krakenbake.exe embedded_krakenbake.wlua krakenbake.exe"
