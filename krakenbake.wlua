-------------------------------------------------------------------------------
--  The Krakenstein Coil-Up Test App. Copyright (c) 2010 Stuart P. Bentley.  --
-------------------------------------------------------------------------------

--This line imports the IUPLua library. (If you experience errors here,
--  make sure that you've got the IUP 3.0 DLLs (or non-Windows equivalent)
--  accessible to your Lua interpreter with the name used here
--  (you may want to try 'require "iuplua51"' instead).
require "iuplua"
require "iuplua_pplot"
require "cdluacontextplus" --to get GDI+ antialiasing and other delights

math.randomseed(os.time()) --For variable damage and square color

-------------------------------------------------------------------------------
-- Parameter Variables
-------------------------------------------------------------------------------

---- Interface --------------------------------------------

--The number of targets (think of it as how many teammates on the map).
--  I chose 8, but you can make it as many or as few as you want.
local playercount = 8

--The size of the bars (and the default height of the target).
local barwidth, barheight = 30, 200

--Size of the graph.
local graph_size="640x480"

--This is the list of colors for the squares.
local colors={
  "255 0 0", "0 0 255", "255 255 0", "0 255 255",
  "255 0 255", "0 255 0", "128 0 0", "255 216 192" }

---- Graphing and Timing ----------------------------------

--How many seconds between each update.
--  On Windows, 10 ms is the shortest duration IUP allows,
--  so .01 is the theoretical minimum.
--  I chose .015 because .01 was giving inaccurate times,
--  and ~67 FPS is plenty.
local timeres = .015

--Number of seconds between graph updates.
local graph_interval=.25

--How many seconds for the graph to span.
local graph_span=30

---- Simulation stats -------------------------------------

------ Player class stats -------------
--for simplicity's sake, I'm treating all players as the
--  same class (a soldier).
local basehealth=200
local maxhealth=300 --Overheal limit

------ Combat slider ------------------

--The maximum attack frequency.
local nightmare=40
--The default attack frequency.
local defaultcombat=10

--The attack power of the random attacks.
local damage=40

--The amount of overheal to lose each second.
--  This is true for all classes, don't change it.
local dissipate=(maxhealth-basehealth)/20

---- Krakenstein stats ------------------------------------

--The maximum time cap, in seconds.
local maxcoil = 2

--The Krakenstein's base healing rate.
local krakenstein_baserate = 12
--The time until The Krakenstein begins its ramp up.
local krakenstein_mintime = 4
--The time it takes for The Krakenstein to reach its maximum heal rate.
local krakenstein_ramplength = 8
--The multiplier of the Krakenstein heal rate.
local krakenstein_multiplier = 4

--How much health The Krakenstein provides to the player in focus.
local boost=0

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--The function that determines how much health to heal.
local healrate; do
  local baserate=krakenstein_baserate
  local mintime=krakenstein_mintime
  local ramplength=krakenstein_ramplength
  local increase=krakenstein_multiplier - 1

  local maxtime=mintime+ramplength

  function healrate(time)
      return
        --The fraction of the distance between the start and the end
        -- of the linear curve (0 if not there yet, 1 if past)
        (((math.max(mintime,math.min(maxtime,time))-mintime)/ramplength
        --Times the amount the multiplier can increase
        --  plus the minimum multiplier (1)
        * increase) + 1)
        * baserate
  end

  function setrate(...)
    baserate, mintime, ramplength, multiplier = ...
    increase = multiplier -1
  end
end

--Function that chooses player colors.
local function color(position)
  if position <= #colors then return colors[position]
  else return string.format("%i %i %i",
    math.random(255), math.random(255), math.random(255))
  end
end

---- Player Data (including controls) ---------------------

--The table storing all players
--  and the table for their column in the window.
local players, vboxes = {}, {}
for i=1,playercount do --This loop is evaluated once for each player
  --Create a table for this player (placed in the players table).
  local player={}; players[i] = player

  --Create the controls for this player.
  player.coilbar = iup.progressbar{
      rastersize = barwidth.."x"..barheight,
      orientation="vertical",
      max = maxcoil}
  player.target = iup.canvas{
    rastersize = barwidth.."x"..barwidth,
    bgcolor = color(i)}
  --The functions for the target to note when the cursor is on it.
  function player.target:enterwindow_cb()
    player.focus=true end
  function player.target:leavewindow_cb()
    player.focus=nil end
  player.health=basehealth
  --start everybody out at the base heal rate
  player.undamaged=0

  --Put the controls together for their column in the window.
  vboxes[i]=iup.vbox{player.coilbar, player.target,
    alignment="ACENTER"}
end

---- Interface Elements (non-player controls) -------------

------ Graph --------------------------

local graph = iup.pplot{marginleft=60,marginbottom=50,
    rastersize=graph_size,
    --Axes should stay on the edges.
    AXS_XCROSSORIGIN="NO",AXS_YCROSSORIGIN="NO",
    AXS_YAUTOMIN="NO", AXS_YMIN=0,
    AXS_YAUTOMAX="NO", AXS_YMAX=maxhealth,
    AXS_XAUTOMIN="NO", AXS_XMIN=-graph_span,
    AXS_XAUTOMAX="NO", AXS_XMAX=0,
    AXS_YLABEL="Health",
    AXS_XLABEL="Elapsed seconds",
    grid="YES",
    ["USE_GDI+"]="YES",
    EXPAND="HORIZONTAL",
  }

for i=0, playercount-1 do --initialize all the data sets
  iup.PPlotBegin(graph, 0)
  iup.PPlotAdd(graph, 0, basehealth)
  iup.PPlotEnd(graph)
  graph.ds_linewidth=2
  graph.ds_color=players[i+1].target.bgcolor
end

------ Krakenstein / Medigun Toggle ---

local krakentoggle=iup.toggle{
  title="Krakenstein",
  value="ON"}
function krakentoggle:action(state)
  if state==1 then
    setrate(krakenstein_baserate,
      krakenstein_mintime,
      krakenstein_ramplength,
      krakenstein_multiplier)
  end
end

local meditoggle=iup.toggle{
  title="Medigun"}
function meditoggle:action(state)
  if state==1 then
    setrate(24,10,5,3)
  end
end

local toggles=iup.radio{iup.vbox{krakentoggle,meditoggle}}

---- Combat slider ----------------------------------------
local combat= iup.val{
  max=nightmare,
  min=0,
  value=defaultcombat,
  --crazy val not naming its type argument!
  type="VERTICAL", [1]="VERTICAL",
  expand="VERTICAL",
  }

------ Labels for combat levels -------
local defaultbold=string.gsub(iup.GetGlobal"DEFAULTFONT",
  "(.+), (%d*)","%1, Bold %2")
local labels=iup.vbox{
  iup.label{title="More Gun", font=defaultbold},
  iup.label{title="Nightmare!"},
  iup.fill{},
  iup.label{title="Ultra-Violence"},
  iup.fill{},
  iup.label{title="Hurt me plenty"},
  iup.fill{},
  iup.label{title="Hey, not too rough"},
  iup.fill{},
  iup.label{title="Less Gun", font=defaultbold},
  iup.label{title="Cease fire!"},
}

--Create the timer that ticks constantly.
local constantly = iup.timer{ time = 1000*timeres }

-------------------------------------------------------------------------------
-- Simulation Loop
-------------------------------------------------------------------------------

do
---- Initialization ---------------------------------------
  --The number of players being healed, updated each frame.
  --  As nobody is being healed at the start, this number is initially 0.
  local healingplayers = 0

  --Index to insert into in dataset (goes up every update).
  local dsindex = 1

  --Time since last graph (for limiting graph update frequency).
  local lastgraph = 0

  --Time elapsed.
  local elapsed_time = 0

---- Loop Function ----------------------------------------
  --The function that is executed each frame.
  function constantly:action_cb()

    --The running total of players being healed this frame.
    local hp_new = 0

---- For each player --------------------------------------
    for i, player in pairs(players) do

      --Let's keep their current coil duration in a local for efficiency
      local coil = tonumber(player.coilbar.value)

------ Heal targeting -----------------
      --if the cursor is currently on this player's target
      --  and the target is not "dead" (no health in combat)
      if player.focus
        and (player.health > 0 or tonumber(combat.value) < 1) then

        --if The Krakenstein is selected
        if krakentoggle.value=="ON" then
          --increase their coil duration
          player.coilbar.value = math.min( coil +
              --with a multiplier of 1 + the current number of heal targets
              timeres * (1+healingplayers),
            maxcoil) --or just to the max if they'd surpass it

          --heal this player alone a little
          player.health=math.min(player.health+boost*timeres,maxhealth)

        else --if the normal Medigun is selected
          player.coilbar.value = maxcoil
        end

          --stupid hack to keep Windows Vista / 7 from slowing the uptake
          player.coilbar.value = player.coilbar.value -.001
          player.coilbar.value = player.coilbar.value +.001

      else --if the cursor is not on their target

        --if The Krakenstein is selected
        if krakentoggle.value=="ON" then
          --reduce the bar (but not past the minimum)
          player.coilbar.value = math.max(coil - timeres,0)

        else --if the normal Medigun is selected
          player.coilbar.value = 0
        end
      end

------ Healing ------------------------
      --If this player still has time left
      if tonumber(player.coilbar.value)>0 then

        --increase the count of players being healed this frame by one
        hp_new=hp_new+1

        --heal this player (up to the max)
        player.health = math.min(player.health +
          healrate(player.undamaged)*timeres,
          maxhealth)

      else --if this player is not currently being healed

        --If they have overheal
        if player.health > basehealth then
          --Dissipate it
          player.health=math.max(player.health-dissipate*timeres,basehealth)
        end
      end

------ Combat -------------------------
      --if the player is hit
      if math.random(math.floor(100/timeres)) <= tonumber(combat.value) then

        --reduce their health (not below 0)
        player.health=math.max(player.health-damage, 0)

        --If player is now dead, remove all coil
        if player.health ==0 then player.coilbar.value=0 end

        --reset their time since last damage
        player.undamaged=0

      else

        --increase time since last taking damage
        player.undamaged=player.undamaged+timeres
      end

------ Graphing (each player) ---------
      --If it's been long enough since the last frame graphed
      if lastgraph >= graph_interval then

        iup.PPlotInsert( -- Plot
          graph, ---------- on the graph
          i-1, ------------ on the current player's line
          dsindex, -------- on a new point
          elapsed_time, --- at this time
          player.health) -- the player's health
      end
    end -- For each player --------------------------------

---- Graphing (all players) -------------------------------
    --If it's been long enough since the last frame graphed
    if lastgraph >= graph_interval then
      --Roll back the timer
      lastgraph=lastgraph-graph_interval

      --Move the graph to the most recent time span
      graph.axs_xmin=elapsed_time-graph_span
      graph.axs_xmax=elapsed_time

      --Redraw the graph by setting the "redraw" attribute to anything
      graph.redraw=nil

      --Increase the index the next points will insert to
      dsindex=dsindex+1
    end

    --update the timers
    lastgraph=lastgraph+timeres
    elapsed_time=elapsed_time+timeres

    --update the number of players being healed stat
    healingplayers=hp_new
  end
end ---------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Program Start
-------------------------------------------------------------------------------

--Create and show the dialog
iup.dialog{iup.hbox{
  iup.vbox{
    iup.hbox(vboxes),
    graph},
  iup.vbox{alignment="ACENTER",
    toggles,
    iup.hbox{
      combat,
      labels}}
  }
  ,title="Krake-n-Bake!"}:show()

--Run the simulation loop
constantly.run="YES"

--Relinquish flow control to IUP
iup.MainLoop()
