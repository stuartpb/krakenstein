-------------------------------------------------------------------------------
--  The Krakenstein Coil-Up Test App. Copyright (c) 2010 Stuart P. Bentley.  --
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- For more information:
-------------------------------------------------------------------------------

local forumthread =
  "http://forums.steampowered.com/forums/showthread.php?t=1164215"

local projectpage = "http://launchpad.net/krakenstein"

-------------------------------------------------------------------------------
-- About This Version
-------------------------------------------------------------------------------

--My general rule with new versions is that I make a new one each time I have
--  to take a new screenshot to represent it. That's how I came up with 1.4
--  for the first "version" (my previous screenshot was named markiii.png).
--  I'll also increment the version when the mechanic changes.
--  Level-3 version numbers are for bugfixes.
local version = "1.4.1";

--When the EXE falls back to its embedded copy of the script, it is called
--  as a function with "exe_message" (the reason that the external file
--  failed to load) as a parameter. That's why exe_message is not defined
--  in this script.

-------------------------------------------------------------------------------
-- Library Requirements
-------------------------------------------------------------------------------

--This line imports the IUPLua library. (If you experience errors here,
--  make sure that you've got the IUP 3.0 DLLs (or non-Windows equivalent)
--  accessible to your Lua interpreter with the name used here
--  (you may want to try 'require "iuplua51"' instead).
require "iuplua"

--This line imports the PPlot library (which is required for the graph)
--  as a pcall. If you don't have it, it will simply replace the function of
--  the graph with a series of progress bars representing the players' health.
--    It will only make the substitution if showgraph is "false" (pcall's
--  return in the event of an error), so you can remove the graph entirely by
--  making it nil (commenting out the pcall'd require altogether).
local showgraph=pcall(require,"iuplua_pplot")

math.randomseed(os.time()) --For variable damage and square color

-------------------------------------------------------------------------------
-- Parameter Variables
-------------------------------------------------------------------------------

---- Interface --------------------------------------------

--The number of targets (think of it as how many teammates on the map).
--  I chose 8, but you can make it as many or as few as you want.
local playercount = 8

--Size of the graph.
local graph_height=400
local graph_width=600 --240 gives the old style thin bars and tiny targets

--The height of the bars and the starting height of the target.
--  Bar widths (etc) are now exclusively determined as
--  graph_width/playercount.
local targetheight, barheight = 64, 200

--The fraction of the target height for the Krakenstein heal targets.
local kst_fraction = 2 --Half (32 pixels)

--This is the list of colors for the squares.
local colors={
  "255 0 0", "0 0 255", "255 255 0", "0 255 255",
  "255 0 255", "0 255 0", "160 64 0", "255 216 192" }

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

--The starting combat slider position.
local defaultcombat=.5

--The attack power of the random attacks.
local damage=40

--The amount of overheal to lose each second.
--  This is true for all classes, don't change it.
local dissipate=(maxhealth-basehealth)/20

---- Krakenstein stats ------------------------------------

--The maximum time cap, in seconds.
local basecoilcap = .5
local addcoilcap= .5

--The base multiplier for coiling up.
local basecoilmul = 1.5
--The additional multiplier for each player being healed.
local addcoilmul = 1.5

--The Krakenstein's base healing rate.
local krakenstein_baserate = 12
--The time until The Krakenstein begins its ramp up.
local krakenstein_mintime = 6
--The time it takes for The Krakenstein to reach its maximum heal rate.
local krakenstein_ramplength = 9
--The multiplier of the Krakenstein heal rate.
local krakenstein_multiplier = 4

--How much health The Krakenstein provides to the player in focus.
local boost = 6

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
  --choose new color for uninitialized positions
  if not colors[position] then
    colors[position] = string.format("%i %i %i",
    math.random(255), math.random(255), math.random(255))
  end

  return colors[position]
end

--Level of combat players are in (how often to successfully roll for damage).
local combat

---- Player Data (including controls) ---------------------

--A function that very slightly decreases a progress bar and re-increases it.
--  Without this stupid hack, the progress bars on Windows Vista/7 will
--  only slowly increase the green level to the value you've set it to,
--  causing them to "snap" suddenly to the correct value when they start
--  unexpectedly decreasing.
local function jig(jigbar)
  jigbar.value = jigbar.value -.001
  jigbar.value = jigbar.value +.001
end

--The maximum possible max coil amount (the full position for all bars).
--Used in player control creation and simulation loop function.
local barmax=basecoilcap+playercount*addcoilcap

--The table storing all players
--  and the table for their coil/target/health text columns in the window.
local players, vboxes = {}, {}

--The table for the bars for their health if the graph is not to be seen
local graph
do
  --Determine the starting width of each player's column
  local barwidth=math.floor(graph_width/playercount)
  local sigbarwidth=barwidth/5
  local coilbarwidth=sigbarwidth*4

  --The font for the health readouts...
  local defaultbig=
    string.gsub(iup.GetGlobal"DEFAULTFONT",--the default font
    " %d*$", string.format(" %i", --with the size replaced
    barwidth/3)) --This approximates a good "fill" of the default width

  --if no graph, determine heights for healthbars and create the table
  local overheal_height, health_height
  if showgraph==false then
    graph={}
    overheal_height=graph_height*((maxhealth-basehealth)/maxhealth)
    health_height=graph_height*(basehealth/maxhealth)
  end


  for i=1,playercount do --This loop is evaluated once for each player
    --Create a table for this player (placed in the players table).
    local player={bars={}}; players[i] = player

    --Create the controls for this player.
    --The progress bar representing how far "coiled" the Krakenstein beam
    --  is around the player.
    player.bars.coil = iup.progressbar{
        rastersize = coilbarwidth.."x"..barheight,
        orientation="vertical",
        expand="horizontal"}

    player.bars.sigmax = iup.progressbar{
        rastersize = sigbarwidth.."x"..barheight,
        orientation="vertical",
        expand="horizontal"}

    local kst_size=targetheight/kst_fraction
    --The colored area to place the cursor in to "target" the player
    --  for healing.
    player.smalltarget = iup.canvas{
      rastersize = kst_size.."x"..kst_size,
      bgcolor = color(i), border="no",
      cx=barwidth/2-kst_size/2, cy=targetheight/2-kst_size/2,}
    --The bigger version for the Medigun.
    player.bigtarget = iup.canvas{
      bgcolor = color(i),
      border="no"}
    --The functions for the target to note when the cursor is on it.
    function player.smalltarget:enterwindow_cb()
      player.focus=true end
    function player.smalltarget:leavewindow_cb()
      player.focus=nil end
    player.bigtarget.enterwindow_cb=
      player.smalltarget.enterwindow_cb
    player.bigtarget.leavewindow_cb=
      player.smalltarget.leavewindow_cb
    player.targetbox = iup.cbox{
      rastersize = barwidth.."x"..targetheight,
      player.smalltarget
    }
    player.target=iup.zbox{player.targetbox,player.bigtarget}

    --The text box reading how much health the player has.
    player.healthtext= iup.text{
      alignment="ACENTER", expand="horizontal",
      value=basehealth, rastersize=barwidth.."x",
      fgcolor="64 64 64", bgcolor="192 192 192",
      font=defaultbig,readonly="yes",
      --text borders have more benefits than drawbacks
      --border="no"
      }

    --start everybody out with base health
    player.health=basehealth
    --start everybody out at the base heal rate
    player.undamaged=0
    --and uncoiled
    player.model={coil=0,sigmax=0}

    function player:setbar(which,value)
      --to save CPU, only update bars when the value actually changes
      if self.model[which]~=value then
        --note if the value is increasing
        local increase = self.model[which] < value

        --update the values
        self.model[which]=value
        self.bars[which].value=value/barmax

        --if the value is increasing, fake a decrease to update it instantly
        if increase then jig(self.bars[which]) end
      end
    end

    --Put the controls together for their column in the window.
    vboxes[i]=iup.vbox{
      iup.hbox{player.bars.coil,player.bars.sigmax},
        player.target, player.healthtext,
      alignment="ACENTER"}

    if showgraph==false then
      --If there's no graph, make health bars for each player
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
  if showgraph==false then
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
      grid="YES", border="no",
      USE_IMAGERGB="YES", FONT="Helvetica, 8",
      EXPAND="HORIZONTAL",
      bgcolor="32 32 32", gridcolor="64 64 64",
      axs_xcolor="128 128 128", axs_ycolor="128 128 128",
    }

  for i=0, playercount-1 do --initialize all the data sets
    iup.PPlotBegin(graph, 0)
    iup.PPlotAdd(graph, 0, basehealth)
    iup.PPlotEnd(graph)
    graph.ds_linewidth=2
    graph.ds_color=color(i+1)
  end
end

------ Krakenstein / Medigun Toggle ---

local function selecttarget (value)
  for i,player in pairs(players) do
    player.target.value=player[value]
  end
end

local krakentoggle=iup.toggle{
  title="Krakenstein",
  value="ON", expand="horizontal"}
function krakentoggle:action(state)
  if state==1 then
    setrate(krakenstein_baserate,
      krakenstein_mintime,
      krakenstein_ramplength,
      krakenstein_multiplier)
    selecttarget "targetbox"
  end
end

local meditoggle=iup.toggle{
  title="Medigun", expand="horizontal"}
function meditoggle:action(state)
  if state==1 then
    setrate(24,10,5,3)
    selecttarget "bigtarget"
  end
end

--create the frame with this radio toggle
local toggles=iup.frame{
  bgcolor="192 192 192",
  iup.radio{
    iup.vbox{
      krakentoggle,
      meditoggle}}}

---- Combat slider ----------------------------------------

local combatslider= iup.val{
  max=1, min=0, --not that these aren't the defaults but, you know
  value=defaultcombat,
  --crazy val not naming its type argument!
  type="VERTICAL", [1]="VERTICAL",
  expand="VERTICAL",
  }

function combatslider:valuechanged_cb()
  if tonumber(self.value) <= .5 then
    combat=10*(tonumber(self.value)/.5)
  else
    combat=10+60*((tonumber(self.value)-.5)/.5)
  end
  --this isn't working for some reason
  self.tip=string.format("Combat level: %i",combat)
end

--initialize the combat value
combatslider:valuechanged_cb()

------ Labels for combat levels -------

--Determine the bold version of the default font for the extremes
local defaultbold=string.gsub(iup.GetGlobal"DEFAULTFONT",
  "(.+), (%d*)","%1, Bold %2")

--Color for the labels
local labelcolor="224 224 224"

--Color for the exteres (the same color by default)
local boldcolor=labelcolor

local labels=iup.vbox{
  iup.label{title="More Gun", font=defaultbold, fgcolor=boldcolor},
  iup.label{title="Nightmare!", fgcolor=labelcolor},
  iup.fill{},
  iup.label{title="Ultra-Violence", fgcolor=labelcolor},
  iup.fill{},
  iup.label{title="Hurt me plenty", fgcolor=labelcolor},
  iup.fill{},
  iup.label{title="Hey, not too rough", fgcolor=labelcolor},
  iup.fill{},
  iup.label{title="Less Gun", font=defaultbold, fgcolor=boldcolor},
  iup.label{title="Cease fire!", fgcolor=labelcolor},
}

-------------------------------------------------------------------------------
-- Simulation Loop
-------------------------------------------------------------------------------


--Create the timer that runs the simulation by ticking constantly.
local simulation = iup.timer{ time = 1000*timeres }

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
  function simulation:action_cb()

    local maxcoil=basecoilcap+healingplayers*addcoilcap

    --The running total of players being healed this frame.
    local hp_new = 0

---- For each player --------------------------------------
    for i, player in pairs(players) do

      --Let's keep their current coil duration in a local for efficiency
      local coil = player.model.coil

------ Heal targeting -----------------
      --if the cursor is currently on this player's target
      --  and the target is not "dead" (no health in combat)
      if player.focus
        and (player.health > 0 or tonumber(combat) < 1) then

        --if The Krakenstein is selected
        if krakentoggle.value=="ON" then
          --increase their coil duration
          player:setbar("coil", math.min( coil +
              --with a multiplier of 1 + the current number of heal targets
              timeres * (basecoilmul+healingplayers*addcoilmul),
            --or just to the max if they'd surpass it (or hold at their
            --current coil amount if they have more than the max)
            math.max(maxcoil,player.model.coil)))

          --heal this player alone a little
          player.health=math.min(player.health+boost*timeres,maxhealth)

        else --if the normal Medigun is selected
          player:setbar("coil",barmax)
        end

      else --if the cursor is not on their target

        --if The Krakenstein is selected
        if krakentoggle.value=="ON" then
          --reduce the coil (but not past the minimum)
          player:setbar("coil",math.max(coil - timeres,0))

        else --if the normal Medigun is selected
          player:setbar("coil",0)
        end
      end

------ Healing ------------------------
      --If this player still has time left
      if tonumber(player.model.coil)>0 then

        --increase the count of players being healed this frame by one
        hp_new=hp_new+1

        --heal this player (but not beyond the max)
        player.health = math.min(player.health +
          healrate(player.undamaged)*timeres,
          maxhealth)

        if krakentoggle.value=="ON" then
          player:setbar("sigmax",maxcoil)
        else
          player:setbar("sigmax",barmax)
        end
      else --if this player is not currently being healed

        --If they have overheal
        if player.health > basehealth then
          --Dissipate it
          player.health=math.max(player.health-dissipate*timeres,basehealth)
        end

        player:setbar("sigmax",0)
      end

------ Combat -------------------------
      --if the player is hit
      if math.random(math.floor(100/timeres)) <= combat then

        --reduce their health (not below 0)
        player.health=math.max(player.health-damage, 0)

        --If player is now dead and they were being healed, stop the healing
        --  and decrement the count of players being healed this frame
        if player.health == 0 and player.model.coil > 0 then
          player:setbar("coil",0)
          hp_new=hp_new-1
        end

        --reset their time since last damage
        player.undamaged=0

      else

        --increase time since last taking damage
        player.undamaged=player.undamaged+timeres
      end

------ Health Display -----------------
      --update the displayed value
      player.healthtext.value=string.format("%i",player.health)
      --update the color
      player.healthtext.bgcolor=
        --light grey if the player is overhealed
        player.health > basehealth and "224 224 224"
        --a darker grey if they have between 100% and 50% health
        or player.health > basehealth/2 and "192 192 192"
        --red if they're below half health but still alive
        or player.health > 0 and "224 0 0"
        --off-black if they're dead
        or "32 32 32"

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
        elseif showgraph==false and player.lastupdate~=player.health then
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
-- Image Creation
-------------------------------------------------------------------------------

--Declaration of the icon that will be used by the dialog at creation
local icon
do
  --square pixel size of both icons
  local size=32
  --edge for procedures
  local edge=size-1

  --function to initialize tables for both
  local make_pixels_table = loadstring(
    string.format("return {%s}",string.rep("0,", size^2)))

  --function returning a new table of the size of the icon
  --  with 0 for all pixels,
  --  followed by a function for making functions that
  --  write pixels in that table by coordinate
  function imagestuff()
    local pixels=make_pixels_table()
    return pixels, function(n)
      return function (x, y)
        pixels[y*size+x+1]=n
      end
    end
  end

  --How "deep in" the "tips" go.
  local depth=10
  --How far apart the edges of these "tips" are.
  local breadth=edge-depth

---- Icon -------------------------------------------------
  local ipixels, ipixel = imagestuff()
  --redefine ipixel to  be the index 1 pixel writer
  ipixel=ipixel(1)

  --make body square
  for y=depth*size,breadth*size,size do
    for x=depth,breadth do
      ipixels[y+x]=1
    end
  end

  --make tips
  for inward=0,depth do
    for tipwide=depth,breadth do
      ipixel(tipwide,      inward) --top
      ipixel(inward,      tipwide) --left
      ipixel(tipwide, edge-inward) --bottom
      ipixel(edge-inward, tipwide) --left
    end
  end

  --create the image to be used for the dialog's icon
  icon=iup.image{width=size, height=size, pixels=ipixels,
    colors={"BGCOLOR","181 32 3"}}

---- Crosshair Cursor -------------------------------------
  local ch_pixels, ch_pindex = imagestuff()

  --How far in from the edges to start at.
  local margin=0
  --How many additional layers to draw.
  local thickness=1

  --Draw from the inside out so we can just overwrite
  --  the indruding segments with the outer edges.
  for t=thickness,0,-1 do
    --Increase color index for each outer layer
    local ch_pixel=ch_pindex(2-t)

    --make tip edges
    for tipwide=depth,breadth do
      ch_pixel(tipwide, margin+t) --top
      ch_pixel(margin+t, tipwide) --left
      ch_pixel(tipwide, (edge-margin)-t) --bottom
      ch_pixel((edge-margin)-t, tipwide) --right
    end

    --make other edges
    for inward=margin, depth+t do
      ch_pixel(inward,           depth+t) --left-top
      ch_pixel(inward,      edge-depth-t) --left-bottom
      ch_pixel(edge-inward,      depth+t) --right-top
      ch_pixel(edge-inward, edge-depth-t) --right-bottom
      ch_pixel(depth+t,           inward) --top-left
      ch_pixel(edge-depth-t,      inward) --top-right
      ch_pixel(depth+t,      edge-inward) --bottom-left
      ch_pixel(edge-depth-t, edge-inward) --bottom-right
    end
  end

  --create the cursor
  local crosshair = iup.image{ width=size, height=size, pixels=ch_pixels,
    colors={
      "BGCOLOR", --transparency
      "200 192 160", --the brightest point on the actual crosshair
      "255 244 204"  --the brightest shade of that color so we can see it
    }, hotspot="16:16"}

  --assign it to each player's targets
  for i=1,playercount do
    players[i].bigtarget.cursor=crosshair
    players[i].smalltarget.cursor=crosshair
  end
end

---------------------------------------------------------------------------------
-- Dialog Creation
---------------------------------------------------------------------------------

--declare the main window to show when starting the program
local mainwindow
do
  --Function for making links
  local function link_to(url)
    return function(self) iup.Help(url) end
  end

  --Function to close the dialog and resume the simulation loop
  local function close_and_resume(self)
    simulation.run = "YES"
    return iup.CLOSE
  end

  --Create the about dialog
  local about
  if exe_message then
    about=iup.dialog{
    title="About Krake-n-Bake", dialogframe="YES",
    close_cb=close_and_resume;
    iup.vbox{alignment="ACENTER",nmargin="5x5",gap="3x3",
      iup.vbox{alignment="ACENTER",
        iup.label{title=string.format(
          "The Krakenstein Test App %s",version)},
        iup.button{title="Forum thread", action=link_to(forumthread),
          size="100x12"},
        iup.button{title="Launchpad project", action=link_to(projectpage),
          size="100x12"},
      },
      iup.label{title="External file load attempt results:"},
      iup.label{title=exe_message},
      iup.hbox{
        iup.fill{},
        iup.button{title="OK",size="50x12",action=close_and_resume}}}}
  else
    about=iup.dialog{
    title="About Krake-n-Bake", dialogframe="YES",
    size="150x70",close_cb=close_and_resume;
    iup.vbox{alignment="ACENTER",nmargin="5x5",
      iup.vbox{alignment="ACENTER",
        iup.label{title=string.format(
          "The Krakenstein Test App %s",version)},
        iup.button{title="Forum thread", action=link_to(forumthread),
          size="100x12"},
        iup.button{title="Launchpad project", action=link_to(projectpage),
          size="100x12"},
      },
      iup.fill{},
      iup.hbox{
        iup.fill{},
        iup.button{title="OK",size="50x12",action=close_and_resume}}}}
  end

  --Create the main window
  mainwindow=iup.dialog{
    iup.hbox{
      iup.vbox{
        vboxes,
        graph},
      iup.vbox{alignment="ACENTER",
        toggles,
        iup.hbox{
          combatslider,
          labels},
        iup.button{
          title="About...",expand="horizontal",
          action=function()
            simulation.run = "NO"
            about:popup()
            end
          }}};
    --change the title to signify if the script is running from the EXE
    title= exe_message and "Krake-n-Bake.EXE!" or "Krake-n-Bake!",
    icon=icon,
    bgcolor="96 96 96"}
end

-------------------------------------------------------------------------------
-- Program Start
-------------------------------------------------------------------------------

--Show the main window
mainwindow:show()

--Run the simulation loop
simulation.run="YES"

--Relinquish flow control to IUP
iup.MainLoop()
