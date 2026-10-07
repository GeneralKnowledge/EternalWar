--[[
  Limit Theory Wallpaper Generator

  Thin App over Josh Parnell's LT generation + render stack.
  Usage (via configure.py run / lt binary):

    bin/lt64r Wallpaper seed=42 width=1920 height=1080 out=out/wp.png preset=ship

  Flags (key=value):
    seed=<uint64>       System seed (default: time-based)
    width=<int>         Window / export width (default 1920)
    height=<int>        Window / export height (default 1080)
    out=<path>          PNG output path (default ./wallpaper/lt_<seed>_<preset>.png)
    preset=<name>       nebula | ship | asteroids | planet  (default ship)
    frames=<int>        Settle frames before capture (default 4)
    interactive=1       Keep window open; F12 captures, Esc quits
    nebulaRes=<int>     Override Config.gen.nebulaRes (default keep Config)
]]

local Entities = requireAll('Game.Entities')
local DebugControl = require('Game.Controls.DebugControl')

local Wallpaper = Application()
-- Parsed at module load: Application:run calls getDefaultSize before onInit.
Wallpaper.opts = nil

local PRESETS = {
  nebula = true,
  ship = true,
  asteroids = true,
  planet = true,
}

local function parseArgs ()
  local opts = {
    seed = nil,
    width = 1920,
    height = 1080,
    out = nil,
    preset = 'ship',
    frames = 4,
    interactive = false,
    nebulaRes = nil,
  }
  local args = rawget(_G, '__args__') or {}
  for i = 1, #args do
    local a = args[i]
    local k, v = a:match('^([%w_]+)=(.*)$')
    if not k then
      -- bare token: treat as seed if numeric, else preset name
      if PRESETS[a] then
        opts.preset = a
      elseif a:match('^%d+$') then
        opts.seed = a
      else
        printf('Wallpaper: ignoring unrecognized arg <%s>', a)
      end
    elseif k == 'seed' then
      opts.seed = v
    elseif k == 'width' then
      opts.width = tonumber(v) or opts.width
    elseif k == 'height' then
      opts.height = tonumber(v) or opts.height
    elseif k == 'out' then
      opts.out = v
    elseif k == 'preset' then
      opts.preset = v
    elseif k == 'frames' then
      opts.frames = math.max(1, math.floor(tonumber(v) or opts.frames))
    elseif k == 'interactive' then
      opts.interactive = (v == '1' or v == 'true' or v == 'yes')
    elseif k == 'nebulaRes' then
      opts.nebulaRes = tonumber(v)
    else
      printf('Wallpaper: ignoring unrecognized flag <%s>', k)
    end
  end
  if not PRESETS[opts.preset] then
    printf('Wallpaper: unknown preset <%s>, using ship', tostring(opts.preset))
    opts.preset = 'ship'
  end
  return opts
end

local function parseSeed (s)
  if s == nil or s == '' then
    return RNG.FromTime():get64()
  end
  -- Prefer exact uint64 literal when the string is all digits.
  if s:match('^%d+$') then
    local ok, seed = pcall(function ()
      return loadstring('return ' .. s .. 'ULL')()
    end)
    if ok and seed ~= nil then return seed end
  end
  local n = tonumber(s)
  if n then
    return RNG.Create(math.floor(n)):managed():get64()
  end
  -- String hash → seed
  local rng = RNG.FromTime()
  for i = 1, #s do
    rng:get64()
    -- mix character into a fresh FromTime-derived stream via choose index
  end
  return RNG.Create(1 + (#s * 1315423911) % 2147483647):managed():get64()
end

function Wallpaper:ensureOpts ()
  if not self.opts then
    self.opts = parseArgs()
  end
  return self.opts
end

function Wallpaper:getDefaultSize ()
  local o = self:ensureOpts()
  return o.width, o.height
end

function Wallpaper:getTitle ()
  local o = self:ensureOpts()
  return string.format('LT Wallpaper — %s', o.preset)
end

function Wallpaper:getWindowMode ()
  -- Borderless-friendly; still Shown so GL context exists under Xvfb.
  return Bit.Or32(WindowMode.Shown, WindowMode.Resizable)
end

function Wallpaper:generate ()
  local seed = parseSeed(self.opts.seed)
  self.seed = seed
  printf('Wallpaper seed: %s  preset: %s  size: %dx%d',
    tostring(seed), self.opts.preset, self.opts.width, self.opts.height)

  if self.opts.nebulaRes then
    Config.gen.nebulaRes = self.opts.nebulaRes
  end

  -- Clean export: no HUD metrics strip
  Config.debug.metrics = false
  Config.render.vsync = false

  if self.system then self.system:delete() end
  self.system = Entities.System(seed)

  local ship
  do
    ship = self.system:spawnShip()
    ship:setPos(Config.gen.origin)
    ship:setFriction(0)
    ship:setSleepThreshold(0, 0)
    ship:setOwner(self.player)
    self.system:addChild(ship)
    self.player:setControlling(ship)
  end

  local preset = self.opts.preset
  if preset == 'asteroids' or preset == 'ship' then
    self.system:spawnAsteroidField(80, 8)
  end
  if preset == 'planet' then
    self.system:spawnPlanet()
  end
  if preset == 'nebula' then
    -- Hide the player ship far away so the sky reads cleanly
    ship:setPos(Vec3f(1e7, 1e7, 1e7))
  end

  self.focus = ship
  if preset == 'planet' then
    for _, child in self.system:iterChildren() do
      if child ~= ship and child.getScale then
        -- Prefer the planet as orbit target when present
        local ok, scale = pcall(function () return child:getScale() end)
        if ok and scale and scale > 1000 then
          self.focus = child
          break
        end
      end
    end
  end
end

function Wallpaper:applyCamera ()
  self.gameView:setOrbit(true)
  local cam = self.gameView.camera
  cam:setSmooth(false)
  cam:setTarget(self.focus)
  local preset = self.opts.preset
  if preset == 'nebula' then
    cam:setRadius(40)
    cam:setPitch(0.15)
    cam:setYaw(-1.2)
  elseif preset == 'asteroids' then
    cam:setRadius(180)
    cam:setPitch(0.35)
    cam:setYaw(-0.8)
  elseif preset == 'planet' then
    cam:setRadius(self.focus.getScale and (self.focus:getScale() * 3.5) or 8000)
    cam:setPitch(0.25)
    cam:setYaw(-Math.Pi2)
  else -- ship
    cam:setRadius(28)
    cam:setPitch(0.28)
    cam:setYaw(-1.0)
  end
  cam:warp()
end

function Wallpaper:capture ()
  local out = self.opts.out
  if not out or out == '' then
    Directory.Create('./wallpaper')
    out = string.format('./wallpaper/lt_%s_%s.png',
      tostring(self.seed), self.opts.preset)
  else
    local dir = out:match('^(.+)/[^/]+$')
    if dir then Directory.Create(dir) end
  end

  local tex = Tex2D.ScreenCapture()
  tex:save(out)
  tex:free()
  printf('Wallpaper written: %s', out)
  self.wrote = out
end

function Wallpaper:onInit ()
  self:ensureOpts()
  self.player = Entities.Player()
  self:generate()

  DebugControl.ltheory = self
  self.gameView = GUI.GameView(self.player)
  self.canvas = UI.Canvas()
  self.canvas:add(self.gameView
    :add(Controls.MasterControl(self.gameView, self.player)))

  self:applyCamera()

  self.framesLeft = self.opts.frames
  self.captured = false
  self.wrote = nil
end

function Wallpaper:onInput ()
  self.canvas:input()
  if self.opts.interactive then
    if Input.GetPressed(Button.Keyboard.F12) then
      self:capture()
    end
    if Input.GetPressed(Button.Keyboard.Escape) then
      self:quit()
    end
    if Input.GetPressed(Button.Keyboard.R) then
      self:generate()
      self:applyCamera()
    end
  end
end

function Wallpaper:onUpdate (dt)
  self.player:getRoot():update(dt)
  self.canvas:update(dt)

  if not self.opts.interactive and not self.captured then
    self.framesLeft = self.framesLeft - 1
    if self.framesLeft <= 0 then
      self.captured = true
      -- Capture next draw (after this update's draw in Application loop…
      -- Application captures after onDraw when F12; we capture at end of onDraw)
      self.doCapture = true
    end
  end
end

function Wallpaper:onDraw ()
  self.canvas:draw(self.resX, self.resY)
  if self.doCapture then
    self.doCapture = false
    self:capture()
    self:quit()
  end
end

return Wallpaper
