--This is the script I use for charting things in TF2. It's not as heavily commented or formatted as the coil test because I only intended it for internal use-
--  I get pictures from it by taking a screencap of the window and cropping it to the client area.

require "iuplua"
require "iuplua_pplot"

function chart(start, finish, resolution, attributes, finishline)
  --Constant!
  local increment=1/resolution

  local pplot= iup.pplot{marginleft=60,marginbottom=50,
    rastersize="640x480",
    AXS_XAUTOMIN="NO", AXS_XMIN=start,
    AXS_XAUTOMAX="NO", AXS_XMAX=finish,
    AXS_XCROSSORIGIN="NO",AXS_YCROSSORIGIN="NO", --so you can always see the origin
    AXS_YAUTOMIN="NO", AXS_YMIN=0,
    grid="YES",
    legendshow="YES",
    USE_IMAGERGB="YES",
    FONT="TF2, 10"
  }

  for k,v in pairs(attributes) do
    pplot[k]=v
  end

  --following the naming pattern used above for healing- as before, it doesn't matter
  local chart={}

  --Graphs a function along the plot.
  function chart.graph(f,...)
    iup.PPlotBegin(pplot,0)
    for x=start, finish, increment do
      iup.PPlotAdd(pplot, x, f(x))
    end
    iup.PPlotEnd(pplot)
    finishline(pplot, ...)
  end

  --Graphs a function until it hits 0 (the player dies).
  function chart.graphalive(f,...)
    local x, lasthealth = start, f(start)
    iup.PPlotBegin(pplot,0)
    while x<finish and lasthealth>0 do
      iup.PPlotAdd(pplot, x, lasthealth)
      x=x+increment
      lasthealth=f(x)
      if lasthealth<0 then lasthealth=0 end --never end below zero
    end
    iup.PPlotAdd(pplot, x, lasthealth)
    iup.PPlotEnd(pplot)
    finishline(pplot, ...)
  end

  chart.pplot=pplot

  return chart
end

  --baserate: Base healing rate.
  --mintime: Number of seconds until beginning the ramp up.
  --ramplength: Number of seconds until reaching the max rate.
  --multiplier: Multiplier of max rate.
function healing(baserate, mintime, ramplength, multiplier)
  --some constants from these parameters...
  local increase = multiplier-1
  local mintime_health = mintime*baserate
  local acceleration = (baserate*increase)/ramplength
  local maxtime = mintime+ramplength
  local maxrate = baserate*multiplier
  local maxtime_health = mintime_health + (acceleration*ramplength^2)/2+ramplength*baserate

  --Yeah, I'm using my own function name for a variable inside the function, so?
  --This function is NOT going to need recursion.
  local healing={}

  --returns health restored per second if it has been time_since_damage
  --since the player was hit.
  function healing.healrate(time_since_damage)
    return (((math.max(mintime,math.min(maxtime,time_since_damage))-mintime)/ramplength*increase)+1)*baserate
  end

  --Returns total health recovered if it has been (time) seconds after last taking damage.
  function healing.recovery(time)
    if time <= mintime then
      return baserate*time
    elseif time < maxtime then
      local ramptime = time-mintime
      return mintime_health
        +(acceleration*ramptime^2)/2
        +ramptime*baserate
    else
      return maxtime_health + maxrate*(time-maxtime)
    end
  end

  return healing
end

--returns function defining player health under fire
function healingdamage(init_health, max_health, hits_per_sec, damage_per_hit,
  heal_start_time, dmg_end_time)
  return function(time)
    local final_health=
      init_health - math.floor(
        hits_per_sec * math.min(
          time, dmg_end_time or time)
        ) * damage_per_hit
    if heal_start_time and time > heal_start_time then
      --assuming the rate-of-fire is more than .1 hits per second
      --causing the heal rate to never go above 24 HP/s
      --seems like a safe assumption
      final_health = final_health+(time-heal_start_time)*24
    end
    return math.min(max_health, final_health)
  end
end

soldier_sentry = healingdamage(200, 300, 4, 16)
soldier_assisted = healingdamage(200, 300, 4, 16, 0)
soldier_takes_cover = healingdamage(200, 300, 4, 16, 2.5, 3)
soldier_heavy = healingdamage(200, 300, 10, 30, 1, 2)

local function nameline(pplot, legend)
  pplot.ds_legend = legend
  pplot.ds_linewidth = 2
end

--~ soldiers=chart(0, 5.1, 1024, {
--~   title="Health Recovery and Taking Damage",--"Cumulative Healing Over Time", --"Rates of Healing", --
--~   AXS_YLABEL="Health",-- per second", --"Health",
--~   AXS_XLABEL="Time (in seconds)"--"Seconds since last damage taken"--"Time (in seconds)"
--~ },nameline)

--~ soldiers.graphalive(soldier_assisted,"Soldier with Medic buddy vs. L1 Sentry")
--~ soldiers.graphalive(soldier_takes_cover,"Soldier vs. L1 sentry, Medic starts healing after 2.5 seconds, Soldier takes cover after 3")

local function namecolor(pplot, legend, color, thickness)
  pplot.ds_legend = legend
  pplot.ds_color = color
  pplot.ds_linewidth = thickness or 2
end

health=chart(0, 20, 1, {
  title="Healing Ramp", --"Cumulative Healing Over Time", --
  AXS_YLABEL="Health per second",
  AXS_XLABEL="Seconds since last damage taken",
  LEGENDPOS="bottomright"
},namecolor)

medigun = healing(24, 10, 5, 3)
krakenstein = healing(12, 6, 8, 4)
krakenstein_old = healing(12, 4, 8, 4)

health.graph(krakenstein_old.healrate,"Krakenstein (old)","224 224 255")
health.graph(medigun.healrate,"Medigun","255 0 0",3)

local maxplayers=8
local reddiv=64/maxplayers
local greendiv=128/maxplayers
for hts=1,8 do
  local colpos=maxplayers-hts+1
  health.graph(function(x) return krakenstein.healrate(x)+6/hts end,
  "Krakenstein ("..hts.." target avg.)",
  string.format("%i %i 255",reddiv*colpos+64,greendiv*colpos+64),
  hts<=5 and 2 or 1)
end
health.graph(krakenstein.healrate,"Krakenstein (base)","0 0 255",3)

chartwin=iup.dialog{
  health.pplot
}

chartwin:show()
iup.MainLoop()
