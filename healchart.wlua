--This is the script I use for charting things in TF2.
--  It's not as heavily commented or formatted as Krake-N-Bake
--  because I only intended it for internal use-
--  I get pictures from it by taking a screencap of the window
--  and cropping it to the client area.

require "iuplua"
require "iuplua_pplot"

function chart(start, finish, resolution, attributes, finishline)
  --Constant!
  local increment=1/resolution

  local pplot= iup.pplot{marginleft=60,marginbottom=50,
    rastersize="640x480",
    AXS_XAUTOMIN="NO", AXS_XMIN=start,
    AXS_XAUTOMAX="NO", AXS_XMAX=finish,
     --Keep the axes on the edges
    AXS_XCROSSORIGIN="NO",AXS_YCROSSORIGIN="NO",
    AXS_YAUTOMIN="NO", AXS_YMIN=0,
    grid="YES",
    legendshow="YES",
    USE_IMAGERGB="YES",
    FONT="TF2, 10"
  }

  for k,v in pairs(attributes) do
    pplot[k]=v
  end

  local chartt={}

  --Graphs a function along the plot.
  function chartt.graph(f,...)
    iup.PPlotBegin(pplot,0)
    for x=start, finish, increment do
      iup.PPlotAdd(pplot, x, f(x))
    end
    iup.PPlotEnd(pplot)
    finishline(pplot, ...)
  end

  --Graphs a function until it hits 0 (the player dies).
  function chartt.graphalive(f,...)
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

  chartt.pplot=pplot

  return chartt
end

--[=[-- Medical Retreat Awareness Campaign graph ------

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

medichart=chart(0, 5.1, 1024, {
  title="Health Recovery and Taking Damage",
  AXS_YLABEL="Health",
  AXS_XLABEL="Time (in seconds)"
},nameline)

medichart.graphalive(soldier_assisted,
  "Soldier with Medic buddy vs. L1 Sentry")
medichart.graphalive(soldier_takes_cover,
  table.concat({
    "Soldier vs. L1 sentry",
    "Medic starts healing after 2.5 seconds",
    "Soldier takes cover after 3"},", ")

--]=]--------------------------------------------------------------------------

---[=[-- Krakenstein Heal Ramps ------

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
  local maxtime_health = mintime_health +
    (acceleration*ramplength^2)/2+ramplength*baserate

  local healingt={}

  --returns health restored per second if it has been (time) seconds
  --after the heal target last took damage.
  function healingt.healrate(time_since_damage)
    return (((math.max(mintime,math.min(maxtime,time_since_damage))-mintime)
      /ramplength*increase)+1)*baserate
  end

  --Returns total health recovered if it has been (time) seconds
  --after the heal target last took damage.
  function healingt.recovery(time)
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

  return healingt
end

local function namecolor(pplot, legend, color, thickness)
  pplot.ds_legend = legend
  pplot.ds_color = color
  pplot.ds_linewidth = thickness or 2
end

medichart=chart(0, 20, 1, {
  title="Healing Ramp",
  AXS_YLABEL="Health per second",
  AXS_XLABEL="Seconds since last damage taken",
  LEGENDPOS="bottomright"
},namecolor)

medigun = healing(24, 10, 5, 3)
krakenstein = healing(12, 6, 9, 4)
krakenstein_old = healing(12, 4, 8, 4)

medichart.graph(krakenstein_old.healrate,"Krakenstein (old)","224 224 255",1)
medichart.graph(medigun.healrate,"Medigun","255 0 0",3)

local maxplayers=8
local reddiv=64/maxplayers
local greendiv=128/maxplayers
for hts=1,maxplayers do
  local colpos=maxplayers-hts+1
  medichart.graph(function(x) return krakenstein.healrate(x)+6/hts end,
  "Krakenstein ("..hts.." target avg.)",
  string.format("%i %i 255",reddiv*colpos+64,greendiv*colpos+64),
  hts<=5 and 2 or 1)
end
medichart.graph(krakenstein.healrate,"Krakenstein (base)","0 0 255",3)

--]=]--------------------------------------------------------------------------

--[=[-- Uber drain rates ------

--The base drain rate, in amount drained per second.
local base_drain = 1/8

function uberdrain(time,targets)
  return (base_drain*time) + (0.5 * base_drain*time * (targets-1))
end

function fulldrain(targets)
  return function(time)
    return 100*math.max(0,1-uberdrain(time,targets))
  end
end

local uber_stay=1

function simdrain(switches)
  local lasttime=0
  local lastuber=1
  return function(time)
    local i=1
    local istarget={}
    local targets=1
    while switches[i] and switches[i][1]<=time do
      if switches[i][1]+uber_stay>time then
        if not istarget[switches[i][2]] then
          istarget[switches[i][2]]=true
          targets=targets+1
        end
      end
      i=i+1
    end
    lastuber=math.max(0,lastuber-uberdrain(time-lasttime,targets))
    lasttime=time
    return 100*lastuber
  end
end

local function namecolor(pplot, legend, color, thickness)
  pplot.ds_legend = legend
  pplot.ds_color = color
  pplot.ds_linewidth = thickness or 2
end

local function pedantic(u)
  return string.gsub(u,"Uber","\220ber")
end

medichart=chart(0, 8, 64, {
  title=pedantic "Ubercharge Drain Rate",
  AXS_YLABEL=pedantic "Ubercharge %",
  AXS_XLABEL="Seconds after activating charge",
  LEGENDPOS="topright"
},namecolor)

--[==[-- Full Drain Slopes --------
local maxplayers=8
local gbdiv=128/maxplayers
for hts=1,maxplayers do
  local colpos=hts-1
  medichart.graph(fulldrain(hts),
  string.format(pedantic "%i Ubercharged %s",hts,
    hts==1 and "teammate" or "teammates"),
  string.format("255 %i %i",gbdiv*colpos+64,gbdiv*colpos+64))
end
--]==]-----------------------------------------------------

---[==[-- Scenarios --------
medichart.graph(fulldrain(1),"Normal Drain","255 0 0")
medichart.graph(simdrain{
  {3,"Soldier"},
  },"Switch at 3 seconds","255 96 96")
--]==]-----------------------------------------------------

--]=]--------------------------------------------------------------------------

chartwin=iup.dialog{
  medichart.pplot
}

chartwin:show()
iup.MainLoop()
