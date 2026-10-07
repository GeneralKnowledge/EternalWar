--[[
  Limit Theory Wallpaper Generator

  Thin App over Josh Parnell's LT generation + render stack — “dreams of LT”:
  sky plates, ships, stations, fleets, and skirmishes from the real engine.

  Usage (via configure.py run / lt binary):

    bin/lt64r Wallpaper seed=42 width=1920 height=1080 out=out/wp.png preset=fleet

  Flags (key=value):
    seed=<uint64>       System seed (default: time-based)
    width=<int>         Window / export width (default 1920)
    height=<int>        Window / export height (default 1080)
    out=<path>          PNG output path
    preset=<name>       sky | nebula | ship | solo | asteroids | planet |
                        station | fleet | skirmish | system
    frames=<int>        Settle frames before capture (default depends on preset)
    interactive=1       Keep window; F12 capture, R regen, Esc quit
    nebulaRes=<int>     Override Config.gen.nebulaRes
]]

local Entities = requireAll('Game.Entities')
local Actions = requireAll('Game.Actions')
local DebugControl = require('Game.Controls.DebugControl')

local Wallpaper = Application()
Wallpaper.opts = nil

local PRESETS = {
  sky = true,
  nebula = true,   -- alias → sky
  ship = true,     -- fighter + asteroid field
  solo = true,     -- fighter only
  asteroids = true,
  planet = true,
  station = true,  -- ShapeLib station + traffic
  fleet = true,    -- lead ship + escorts
  skirmish = true, -- two sides mid-fight
  system = true,   -- station + rocks + ships (vista)
}

local DEFAULT_FRAMES = {
  sky = 4,
  nebula = 4,
  ship = 4,
  solo = 4,
  asteroids = 4,
  planet = 5,
  station = 6,
  fleet = 8,
  skirmish = 18,
  system = 10,
}

local function isSkyPreset (name)
  return name == 'sky' or name == 'nebula'
end

local function parseArgs ()
  local opts = {
    seed = nil,
    width = 1920,
    height = 1080,
    out = nil,
    preset = 'ship',
    frames = nil,
    interactive = false,
    nebulaRes = nil,
  }
  local args = rawget(_G, '__args__') or {}
  for i = 1, #args do
    local a = args[i]
    local k, v = a:match('^([%w_]+)=(.*)$')
    if not k then
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
      opts.frames = math.max(1, math.floor(tonumber(v) or 4))
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
  if not opts.frames then
    opts.frames = DEFAULT_FRAMES[opts.preset] or 4
  end
  return opts
end

local function parseSeed (s)
  if s == nil or s == '' then
    return RNG.FromTime():get64()
  end
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
  return RNG.Create(1 + (#s * 1315423911) % 2147483647):managed():get64()
end

--- Force a fresh ShapeLib hull on the next System:spawnShip().
local function refreshShipType (system)
  system.shipType = nil
end

local function spawnOwnedShip (system, owner, pos)
  refreshShipType(system)
  local ship = system:spawnShip()
  if pos then ship:setPos(pos) end
  ship:setFriction(0)
  ship:setSleepThreshold(0, 0)
  if owner then ship:setOwner(owner) end
  return ship
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
  return Bit.Or32(WindowMode.Shown, WindowMode.Resizable)
end

function Wallpaper:generate ()
  local seed = parseSeed(self.opts.seed)
  self.seed = seed
  local preset = self.opts.preset
  printf('Wallpaper seed: %s  preset: %s  size: %dx%d',
    tostring(seed), preset, self.opts.width, self.opts.height)

  if self.opts.nebulaRes then
    Config.gen.nebulaRes = self.opts.nebulaRes
  end

  Config.debug.metrics = false
  Config.render.vsync = false

  if self.system then self.system:delete() end
  self.system = Entities.System(seed)
  local rng = self.system.rng

  -- Controlling body (required by GameView). Parked far away for sky plates.
  local ship = spawnOwnedShip(self.system, self.player, Config.gen.origin)
  self.player:setControlling(ship)

  self.focus = ship
  self.skyOnly = isSkyPreset(preset)
  self.hideHud = self.skyOnly

  if isSkyPreset(preset) then
    ship:setPos(Vec3f(1e7, 1e7, 1e7))

  elseif preset == 'solo' then
    -- fighter against sky

  elseif preset == 'ship' then
    self.system:spawnAsteroidField(80, 8)

  elseif preset == 'asteroids' then
    self.system:spawnAsteroidField(120, 10)

  elseif preset == 'planet' then
    self.system:spawnPlanet()
    for _, child in self.system:iterChildren() do
      if child ~= ship and child.getScale then
        local ok, scale = pcall(function () return child:getScale() end)
        if ok and scale and scale > 1000 then
          self.focus = child
          break
        end
      end
    end

  elseif preset == 'station' then
    local station = self.system:spawnStation()
    self.focus = station
    self.hideHud = true
    -- Light traffic around the station
    for i = 1, 4 do
      local offset = rng:getSphere():scale(180 + 40 * i)
      local traffic = spawnOwnedShip(self.system, self.player, station:getPos() + offset)
      traffic:pushAction(Actions.Escort(station, offset))
    end

  elseif preset == 'fleet' then
    self.system:spawnAsteroidField(40, 4)
    local escorts = {}
    for i = 1, 8 do
      local offset = rng:getSphere():scale(40 + 12 * i)
      local escort = spawnOwnedShip(self.system, self.player, ship:getPos() + offset)
      escort:pushAction(Actions.Escort(ship, offset))
      insert(escorts, escort)
    end
    self.focus = ship

  elseif preset == 'skirmish' then
    -- Two wings mid-engagement. Extra settle frames let Attack aim/fire.
    local enemy = Entities.Player()
    insert(self.system.players, enemy)
    local wingA, wingB = {}, {}
    for i = 1, 4 do
      local a = spawnOwnedShip(
        self.system, self.player,
        Config.gen.origin + Vec3f(-60 - 15 * i, 8 * (i % 3 - 1), 20 * (i - 2.5)))
      insert(wingA, a)
    end
    ship = wingA[1]
    self.player:setControlling(ship)
    for i = 1, 4 do
      local b = spawnOwnedShip(
        self.system, enemy,
        Config.gen.origin + Vec3f(70 + 15 * i, -6 * (i % 3 - 1), -18 * (i - 2.5)))
      insert(wingB, b)
    end
    for i = 1, #wingA do
      wingA[i]:pushAction(Actions.Attack(wingB[((i - 1) % #wingB) + 1]))
    end
    for i = 1, #wingB do
      wingB[i]:pushAction(Actions.Attack(wingA[((i - 1) % #wingA) + 1]))
    end
    self.focus = ship
    self.hideHud = true

  elseif preset == 'system' then
    -- Reminiscing vista: station, rocks, a few ships under the nebula.
    local station = self.system:spawnStation()
    self.system:spawnAsteroidField(60, 6)
    for i = 1, 5 do
      local offset = rng:getSphere():scale(220 + 30 * i)
      local traffic = spawnOwnedShip(self.system, self.player, station:getPos() + offset)
      traffic:pushAction(Actions.Escort(station, offset))
    end
    -- Park the player stub near the station for camera focus
    ship:setPos(station:getPos() + Vec3f(160, 40, -120))
    self.focus = station
    self.hideHud = true
  end
end

function Wallpaper:applyCamera ()
  self.gameView:setOrbit(true)
  local cam = self.gameView.camera
  cam:setSmooth(false)
  local preset = self.opts.preset

  if self.skyOnly or isSkyPreset(preset) then
    cam:setTarget(nil)
    cam:setCenter(0, 0, 0)
    cam:setRadius(1)
    local sd = self.system.starDir
    if sd then
      local look = Vec3f(-sd.x, -sd.y, -sd.z):normalize()
      cam:setYaw(math.atan2(look.x, look.z))
      cam:setPitch(math.asin(Math.Clamp(look.y, -0.49, 0.49)))
    else
      cam:setPitch(0.12)
      cam:setYaw(-1.1)
    end
  else
    cam:setTarget(self.focus)
    if preset == 'asteroids' then
      cam:setRadius(180)
      cam:setPitch(0.35)
      cam:setYaw(-0.8)
    elseif preset == 'planet' then
      cam:setRadius(self.focus.getScale and (self.focus:getScale() * 3.5) or 8000)
      cam:setPitch(0.25)
      cam:setYaw(-Math.Pi2)
    elseif preset == 'station' then
      cam:setRadius(420)
      cam:setPitch(0.32)
      cam:setYaw(-0.95)
    elseif preset == 'fleet' then
      cam:setRadius(95)
      cam:setPitch(0.22)
      cam:setYaw(-1.15)
    elseif preset == 'skirmish' then
      cam:setRadius(140)
      cam:setPitch(0.18)
      cam:setYaw(-0.7)
    elseif preset == 'system' then
      cam:setRadius(700)
      cam:setPitch(0.28)
      cam:setYaw(-1.25)
    else -- ship / solo
      cam:setRadius(preset == 'solo' and 22 or 28)
      cam:setPitch(0.28)
      cam:setYaw(-1.0)
    end
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
  if self.hideHud or self.skyOnly then
    self.canvas:add(self.gameView)
  else
    self.canvas:add(self.gameView
      :add(Controls.MasterControl(self.gameView, self.player)))
  end

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
