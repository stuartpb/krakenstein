--This is the script I use for charting things in TF2. It's not as heavily commented or formatted as the coil test because I only intended it for internal use-
--  I get pictures from it by taking a screencap of the window and cropping it to the client area.

require "iuplua"
require "iuplua_pplot"
require "cdluacontextplus" --to get GDI+ antialiasing and other delights

--returns health restored per second if it has been time_since_damage
--since the player was hit.
function healrate(time_since_damage)
  local mintime=10
  local ramptime=5
  local multiplier=3
  local baserate=24

  local maxtime=mintime+ramptime

  return (((math.max(mintime,math.min(maxtime,time_since_damage))-mintime)/ramptime*(multiplier-1))+1)*baserate
end

function health_recovered(time_healing, last_damage_time)
  return
end

--returns function defining player health (assuming players don't go more
--than 10 seconds without being hit)
function healingdamage(init_health, max_health, hits_per_sec, damage_per_hit,
  heal_start_time, cover_start_time)
  return function(time)
    return math.min(max_health, init_health
      -(math.floor(hits_per_sec*math.min(time,cover_start_time or time))*damage_per_hit)
      +(math.max(time-(heal_start_time or time),0))*24)
  end
end

soldier_sentry = healingdamage(200, 300, 4, 16)
soldier_assisted = healingdamage(200, 300, 4, 16, 0)
soldier_takes_cover = healingdamage(200, 300, 4, 16, 2.5, 3)
soldier_heavy = healingdamage(200, 300, 10, 30, 1, 2)

healthgraph=  iup.pplot{marginleft=60,marginbottom=50,
  rastersize="640x480",
  AXS_YAUTOMIN="NO", AXS_YMIN=0,
  grid="YES",
  legendshow="YES",
  ["USE_GDI+"]="YES",
  title="Rates of Healing", --"Health Recovery and Taking Damage",
  AXS_YLABEL="Health per second", --"Health",
  AXS_XLABEL="Seconds since last damage taken"--"Time (in seconds)"
  }

local starttime=0
local endtime=20
local resolution=12

function graphalive(f,legend)
  local i, lasthealth =starttime*resolution, f(starttime)
  iup.PPlotBegin(healthgraph,0)
  while i<endtime*resolution and lasthealth>0 do
    iup.PPlotAdd(healthgraph, i/resolution, lasthealth)
    i=i+1
    lasthealth=f(i/resolution)
    if lasthealth<0 then lasthealth=0 end
  end
  iup.PPlotAdd(healthgraph, i/resolution, lasthealth)
  iup.PPlotEnd(healthgraph)
  healthgraph.ds_legend = legend
  healthgraph.ds_linewidth = 2
end

--graphalive(soldier_assisted,"Soldier with Medic buddy vs. L1 Sentry")
--graphalive(soldier_takes_cover,"Soldier vs. L1 sentry, Medic starts healing after 2.5 seconds, Soldier takes cover after 3")

function ks(time_since_damage)
  local mintime=4
  local ramptime=8
  local multiplier=4
  local baserate=12

  local maxtime=mintime+ramptime

  return (((math.max(mintime,math.min(maxtime,time_since_damage))-mintime)/ramptime*(multiplier-1))+1)*baserate
end

graphalive(healrate,"Medigun")
graphalive(ks,"Krakenstein")

chartwin=iup.dialog{
  healthgraph
}

chartwin:show()
iup.MainLoop()
