-------------------------------------------------------------------------------
--  The Krakenstein Coil-Up Test App. Copyright (c) 2010 Stuart P. Bentley.  --
-------------------------------------------------------------------------------

--This line imports the IUPLua library. (If you experience errors here,
--  make sure that you've got the IUP 3.0 DLLs (or non-Windows equivalent)
--  accessible to your Lua interpreter with the name used here
--  (you may want to try 'require "iuplua51"' instead).
require "iuplua"

--This line imports the PPlot library (which is required for the graph)
--  as a pcall. If you don't have it, it will simply remove all graphing
--  from the app rather than failing to launch entirely. (Of course, that
--  graph is now the major feature of the application, so try to include it.)
local showgraph=pcall(require,"iuplua_pplot")

--This line attempts to import the cdluacontextplus library (CanvasDraw's
--  GDI+ functionality). With it, the lines on the graph will draw with
--  anti-aliasing and look nice. Without it, the graph will just draw with
--  regular GDI with no changes necessary, so if it doesn't load correctly,
--  there's no problem. (Although, if it DOES load but the underlying
--  cdcontextplus.dll is missing, then you'll have problems in the form of
--  the graph simply showing up blank.)
pcall(require,"cdluacontextplus")

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
local graph_height=480
local graph_width=600

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
--  Graphing is a strenuous operation, which is why it operates
--  less frequently. When not graphing, updating 9 progress bars 3 times
--  each frame is a snap, but updating 27 progress bars is a bit more
--  processor intensive. For this reason, updating progress bars is
--  similarly throttled (although not as much as graphing).

local graph_interval=showgraph and .25 or .1

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
--  and the table for their coil/target/health text columns in the window.
local players, vboxes = {}, {}

--The table for the bars for their health if the graph is not to be seen
local graph
do
  --determine heights of healthbars if no graph and create the table
  local overheal_height, health_height
  if not showgraph then
    graph={}
    overheal_height=graph_height*((maxhealth-basehealth)/maxhealth)
    health_height=graph_height*(basehealth/maxhealth)
  end

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
    player.healthtext= iup.text{
      alignment="ACENTER",
      value=basehealth,
      readonly="yes"}
    --The functions for the target to note when the cursor is on it.
    function player.target:enterwindow_cb()
      player.focus=true end
    function player.target:leavewindow_cb()
      player.focus=nil end
    player.health=basehealth
    --start everybody out at the base heal rate
    player.undamaged=0

    --Put the controls together for their column in the window.
    vboxes[i]=iup.vbox{player.coilbar, player.target, player.healthtext,
      alignment="ACENTER"}

    if not showgraph then
      --If there's no graph, make health bars
      player.overhealbar=iup.progressbar{
        rastersize = barwidth.."x"..overheal_height,
        orientation = "vertical",
        expand="horizontal",}
      player.healthbar=iup.progressbar{
        rastersize = barwidth.."x"..health_height,
        orientation = "vertical",
        expand="horizontal",
        value=1}
      player.lastupdate=basehealth
      graph[i]=iup.vbox{player.overhealbar, player.healthbar,
        alignment="ACENTER"}
    end
  end

  vboxes=iup.hbox(vboxes)
  if not showgraph then
    graph=iup.hbox(graph)
  end
end

---- Interface Elements (non-player controls) -------------

------ Graph --------------------------

--local graph was declared above
if showgraph then
  graph = iup.pplot{marginleft=60,marginbottom=50,
      rastersize=graph_width..'x'..graph_height,
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

--A function that very slightly decreases a progress bar and re-increases it.
--  Without this stupid hack, the progress bars on Windows Vista/7 will
--  slowly increase the progress bar to the value you've set it to,
--  causing them to "snap" suddenly to the correct value when they start
--  decreasing.
local function jig(jigbar)
  jigbar.value = jigbar.value -.001
  jigbar.value = jigbar.value +.001
end

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
          jig(player.coilbar)

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

------ Health Display -----------------
      player.healthtext.value=string.format("%i",player.health)

------ Graphing (each player) ---------
      --If it's been long enough since the last frame graphed
      if lastgraph >= graph_interval then
        --If there's a graph to show
        if showgraph then
          iup.PPlotInsert( -- Plot
            graph, ---------- on the graph
            i-1, ------------ on the current player's line
            dsindex, -------- on a new point
            elapsed_time, --- at this time
            player.health) -- the player's health

        --if there's no graph to show and the bars need to be updated
        --(save CPU cycles! avoid unnecessary jiggle!)
        elseif player.lastupdate~=player.health then
          player.lastupdate=player.health

          player.overhealbar.value=
            math.max(player.health-basehealth,0)/(maxhealth-basehealth)
          player.healthbar.value=
            math.min(player.health,basehealth)/basehealth

          --stupid hack to keep Windows Vista / 7 from slowing the uptake
          jig(player.overhealbar)
          jig(player.healthbar)
        end
      end
    end -- For each player --------------------------------

---- Graphing (all players) -------------------------------
    --If it's been long enough since the last frame graphed
    if lastgraph >= graph_interval then
      --Roll back the timer
      lastgraph=lastgraph-graph_interval

      if showgraph then
        --Move the graph to the most recent time span
        graph.axs_xmin=elapsed_time-graph_span
        graph.axs_xmax=elapsed_time

        --Redraw the graph by setting the "redraw" attribute to anything
        graph.redraw=nil

        --Increase the index the next points will insert to
        dsindex=dsindex+1
      end
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
    vboxes,
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
