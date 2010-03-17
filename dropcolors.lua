--This is the script I used to fade the paragraph on healing ramps in the original post. I added the bold tags to the output by hand.

local start=0xE5
local final=0x80

local text=[=[
In this chart, I'm giving the Krakenstein a 12 HP/s rate of healing - half of the normal Medigun's base rate of 24. However, while the Medigun begins its ramp up after 10 seconds without taking damage, the Krakenstein starts ramping up its healing after only 4 seconds. With a multiplier of 4 times the base rate over 8 seconds (versus the original's 3 over 5), the Krakenstein heals faster in the window between 6 to 13 seconds after taking damage than the normal medigun (although, cumulatively, the normal Medigun always has the upper hand). Numbers numbers numbers
]=]

--total steps
local steps=math.min((start-final)+1, #text)
--number of characters per step
local stride=(#text/steps)
--colors per step (1 unless there are more colors than letters)
local grade= #text > start-final and 1 or math.floor(start-final/#text)

local finalstring={}
local color=start
for i=1, steps do
  finalstring[i]=
    string.format('[COLOR=#%01x%01x%01x]%s[/COLOR]',color, color, color,
    string.sub(text, math.floor((i-1)*stride), math.floor(i*stride)-1))
  color=color-grade
end

print(table.concat(finalstring))

--[[
[I]“Ubi concordia, ibi victoria: divided we fall, united we stand. Unity is strength, and knowing is half the battle.”[/I]

– Theodore "Gung Ho" Roosevelt, Address at Milwaukee, 1912
]]
