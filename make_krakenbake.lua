krakenbake=io.open("krakenbake.wlua","r")
embed=io.open("embedded_krakenbake.wlua","w")
embed:write[[
local external = loadfile "krakenbake.wlua"
if external then external()
else
]]
for lines in krakenbake:lines() do embed:write(lines,'\n') end
embed:write"end\n"
krakenbake:close()
embed:close()
os.execute"glue empty_krakenbake.exe embedded_krakenbake.wlua krakenbake.exe"
