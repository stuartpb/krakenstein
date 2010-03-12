-------------------------------------------------------------------------------
--  The Krakenstein Coil-Up Test App. Copyright (c) 2010 Stuart P. Bentley.  --
-------------------------------------------------------------------------------

--This line imports the IUPLua library. (If you experience errors here,
--  make sure that you've got the IUP 3.0 DLLs (or non-Windows equivalent)
--  accessible to your Lua interpreter with the name used here
--  (you may want to try 'require "iuplua51"' instead).
require "iuplua"

--The number of targets (think of it as how many teammates on the map).
--  I chose 8, but you can make it as many or as few as you want.
local playercount = 8

--The width of each bar in the window (and height and width of the target).
--  The way it's set up now, each bar is 30 pixels wide
--  unless it would cause the window to be narrower than 180 pixels,
--  in which case it will make the bars wider.
--  If you change this, keep in mind that IUP 3.0 can create the window
--  narrower than the OS would normally permit.
local barwidth = math.max(180/playercount, 30)

--The height of the bars.
local barheight = 200

--This is the list of colors for the squares.
local colors={
  "255 0 0", "0 0 255", "255 255 0", "0 255 255",
  "255 0 255", "0 255 0", "128 0 0", "128 255 255" }
math.randomseed(os.time()) --This is for colors after the listed ones.

function color(position) --This function chooses from these colors.
  if position <= #colors then return colors[position]
  else return string.format("%i %i %i",
    math.random(255), math.random(255), math.random(255))
  end
end

--The maximum time cap, in seconds.
local maxtime = 2

--The table storing all players
--  and the table for their column in the window.
local players, vboxes = {}, {}
for i=1,playercount do --This loop is evaluated once for each player
  --Create a table for this player (placed in the players table).
  local player={}; players[i] = player

  --Create the controls for this player.
  player.pbar = iup.progressbar{
      rastersize = barwidth.."x"..barheight,
      orientation="vertical",
      max = maxtime}
  player.target = iup.canvas{
    rastersize = barwidth.."x"..barwidth,
    bgcolor = color(i)}
  --The functions for the target to note when the cursor is on it.
  function player.target:enterwindow_cb()
    player.focus=true end
  function player.target:leavewindow_cb()
    player.focus=nil end

  --Put the controls together for their column in the window.
  vboxes[i]=iup.vbox{player.pbar, player.target,
    alignment="ACENTER"}
end

--How many seconds between each tick of the timer.
--  On Windows, 10 ms is the shortest duration IUP allows,
--  so .01 is the theoretical minimum.
--  I chose .015 because .01 was giving inaccurate times,
--  and ~67 FPS is plenty.
local timeres = .015

--Create the timer that ticks constantly.
local constantly = iup.timer{ time = 1000*timeres }

do  -- The coiling functionality. ---------------------------------------------
  --The number of players being healed, updated each frame.
  --  As nobody is being healed at the start, this number is initially 0.
  local healingplayers = 0

  --The function that is executed each frame.
  function constantly:action_cb()
    --The running total of players being healed this frame.
    local hp_new = 0

    for i, player in pairs(players) do --For each player
      --Let's keep their current coil duration in a local for efficiency
      local coil = tonumber(player.pbar.value)

      --if the cursor is currently on this player's target
      if player.focus then
        --increase their coil duration
        player.pbar.value = math.min( coil +
            --with a multiplier of 1 + the current number of heal targets
            timeres * (1+healingplayers),
          maxtime) --or just to the max if they'd surpass it

          --stupid hack to keep Windows Vista / 7 from slowing the uptake
          player.pbar.value = player.pbar.value -.001
          player.pbar.value = player.pbar.value +.001
      else --if the cursor is not on their target
        --reduce the bar (but not past the minimum)
        player.pbar.value = math.max(coil - timeres,0)
      end

      --If this player still has time left
      if tonumber(player.pbar.value)>0 then
        --increase the count of players being healed this frame by one
        hp_new=hp_new+1 end
    end
    healingplayers=hp_new
  end
end ---------------------------------------------------------------------------
constantly.run="YES"

iup.dialog{iup.hbox(vboxes),title="Coil-Up!"}:show()

iup.MainLoop()
