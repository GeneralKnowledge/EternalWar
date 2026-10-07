--[[
  Limit Theory Wallpaper Generator

  Thin App over Josh Parnell's LT generation + render stack — “dreams of LT”:
  sky plates, ships, stations, fleets, and skirmishes from the real engine.

  Usage (via configure.py run / lt binary):

    bin/lt64r Wallpaper seed=42 width=1920 height=1080 out=out/wp.png preset=fleet

    # Keep the process loaded — cycle N plates, then quit (one engine launch):
    bin/lt64r Wallpaper count=8 preset=fleet outdir=wallpaper/batch
    bin/lt64r Wallpaper count=6 presets=fleet,skirmish,station,system outdir=wallpaper/dreams

    # Capitals + auto-pick (via tools/wallpaper.sh best=N):
    ./tools/wallpaper.sh best=6 preset=capital out=wallpaper/best.png
    ./tools/wallpaper.sh best=6 preset=armada out=wallpaper/armada.png

  Flags (key=value):
    seed=<uint64>       System seed (default: time-based); batch advances from it
    width=<int>         Window / export width (default 1920)
    height=<int>        Window / export height (default 1080)
    out=<path>          PNG path (count=1) or stem template (count>1 → stem_001.png)
    outdir=<path>       Directory for batch PNGs (preferred when count>1)
    preset=<name>       sky | nebula | ship | solo | asteroids | planet |
                        station | fleet | skirmish | system | capital | armada
    presets=<a,b,...>   Cycle these presets across the batch (overrides preset)
    count=<int>         Captures before quit; process stays loaded (default 1)
    frames=<int>        Settle frames before capture (default depends on preset)
    interactive=1       Keep window; F12 capture, R regen, Esc quit
    nebulaRes=<int>     Override Config.gen.nebulaRes

  Wrapper-only (tools/wallpaper.sh):
    best=<int>          Bake N candidates in one launch; keep the highest-scoring PNG
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
  capital = true,  -- Gen.ShipCapital sausage
  armada = true,   -- capital + fighter screen
}

local DEFAULT_FRAMES = {
  sky = 4,
  nebula = 4,
  ship = 4,
  solo = 4,
  asteroids = 4,
  planet = 5,
  station = 6,
  fleet = 4,
  -- Turret volleys need a few frames for pulses to be in-flight; no Attack AI.
  skirmish = 10,
  system = 10,
  capital = 5,
  armada = 5,
}

local CAPITAL_SCALE = 48
local FIGHTER_SCALE = 4

local function isSkyPreset (name)
  return name == 'sky' or name == 'nebula'
end

local function splitPresets (csv)
  local list = {}
  if not csv or csv == '' then return list end
  for part in string.gmatch(csv, '[^,]+') do
    local name = part:match('^%s*(.-)%s*$')
    if name and name ~= '' then
      if PRESETS[name] then
        insert(list, name)
      else
        printf('Wallpaper: ignoring unknown preset in list <%s>', name)
      end
    end
  end
  return list
end

local function parseArgs ()
  local opts = {
    seed = nil,
    width = 1920,
    height = 1080,
    out = nil,
    outdir = nil,
    preset = 'ship',
    presets = nil,
    count = 1,
    frames = nil,
    framesExplicit = false,
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
    elseif k == 'outdir' then
      opts.outdir = v
    elseif k == 'preset' then
      opts.preset = v
    elseif k == 'presets' then
      opts.presets = splitPresets(v)
    elseif k == 'count' then
      opts.count = math.max(1, math.floor(tonumber(v) or 1))
    elseif k == 'frames' then
      opts.frames = math.max(1, math.floor(tonumber(v) or 4))
      opts.framesExplicit = true
    elseif k == 'interactive' then
      opts.interactive = (v == '1' or v == 'true' or v == 'yes')
    elseif k == 'nebulaRes' then
      opts.nebulaRes = tonumber(v)
    else
      printf('Wallpaper: ignoring unrecognized flag <%s>', k)
    end
  end
  if opts.presets and #opts.presets > 0 then
    opts.preset = opts.presets[1]
  elseif not PRESETS[opts.preset] then
    printf('Wallpaper: unknown preset <%s>, using ship', tostring(opts.preset))
    opts.preset = 'ship'
  end
  if not opts.frames then
    opts.frames = DEFAULT_FRAMES[opts.preset] or 4
  end
  -- Batch mode never uses the interactive keep-alive path.
  if opts.count > 1 then
    opts.interactive = false
  end
  return opts
end

local function seedToArg (seed)
  -- tostring(uint64) may append "ULL"; CLI / next-plate args want digits only.
  local s = tostring(seed)
  return (s:gsub('[Uu][Ll][Ll]$', ''))
end

local function parseSeed (s)
  if s == nil or s == '' then
    return RNG.FromTime():get64()
  end
  if type(s) == 'string' then
    s = s:gsub('[Uu][Ll][Ll]$', '')
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

--- Bind fighter or capital generator before spawnShip().
local function bindShipType (system, kind, scale)
  local gen = Gen.Ship.ShipFighter
  local scl = scale or FIGHTER_SCALE
  if kind == 'capital' then
    gen = Gen.Ship.ShipCapital
    scl = scale or CAPITAL_SCALE
  end
  system.shipType = ShipType(system.rng:get31(), gen, scl)
end

local function faceToward (entity, forward)
  entity:setRot(Quat.FromLookUp(forward:normalize(), Vec3f(0, 1, 0)))
end

--- Spawn a ship. reuseType=true keeps the current ShapeLib hull (fleet cohesion).
--- kind: nil/'fighter'/'capital' — ignored when reuseType is true.
local function spawnOwnedShip (system, owner, pos, reuseType, kind, scale)
  if not reuseType then
    if kind == 'capital' or kind == 'fighter' then
      bindShipType(system, kind, scale)
    else
      refreshShipType(system)
    end
  end
  local ship = system:spawnShip()
  if pos then ship:setPos(pos) end
  ship:setFriction(0)
  ship:setSleepThreshold(0, 0)
  if owner then ship:setOwner(owner) end
  return ship
end

local function camRadiusFor (entity, mult, fallback)
  local ok, rad = pcall(function () return entity:getRadius() end)
  if ok and rad and rad > 1 then
    return math.max(fallback * 0.5, rad * (mult or 3.2))
  end
  return fallback
end

--- Plate camera: optional world center, or follow entity (camFollow).
local function setPlateCamera (app, center, radius, yaw, pitch)
  app.camCenter = center
  app.camRadius = radius
  app.camYaw = yaw
  app.camPitch = pitch
end

local function fireTurretsAt (from, at)
  if not from or not at then return end
  local pos = at:getPos()
  for turret in from:iterSocketsByType(SocketType.Turret) do
    turret:aimAtTarget(at, pos)
    turret:fire()
  end
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

  -- Controlling body (required by GameView). Capitals use Gen.ShipCapital.
  local startKind = 'fighter'
  if preset == 'capital' or preset == 'armada' then
    startKind = 'capital'
  end
  local ship = spawnOwnedShip(
    self.system, self.player, Config.gen.origin, false, startKind)
  self.player:setControlling(ship)

  self.focus = ship
  self.skyOnly = isSkyPreset(preset)
  self.hideHud = self.skyOnly
  self.camCenter = nil
  self.camRadius = nil
  self.camYaw = nil
  self.camPitch = nil
  self.camFollow = nil
  self.skirmishPairs = nil

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
    -- Light traffic around the station (local offsets for Escort)
    for i = 1, 4 do
      local offset = Vec3f(
        (i % 2 == 0 and 1 or -1) * (90 + 35 * i),
        10 * (i - 2),
        70 + 20 * i)
      local traffic = spawnOwnedShip(self.system, self.player, station:getPos() + offset, true)
      faceToward(traffic, Vec3f(0, 0, 1))
      traffic:pushAction(Actions.Escort(station, offset))
    end

  elseif preset == 'fleet' then
    -- Static V in frame. Do NOT push Escort: toWorldScaled×shipScale flings
    -- escorts to 4× offsets and they leave the plate during settle.
    local origin = Config.gen.origin
    local forward = Vec3f(0, 0, 1)
    ship:setPos(origin)
    faceToward(ship, forward)
    local slots = {
      Vec3f(-14,  3, -12),
      Vec3f( 14, -2, -12),
      Vec3f(-28,  5, -26),
      Vec3f( 28,  1, -26),
      Vec3f(-42,  2, -42),
      Vec3f( 42, -3, -42),
      Vec3f(  0,  7, -22),
    }
    for i = 1, #slots do
      local escort = spawnOwnedShip(self.system, self.player, origin + slots[i], true)
      faceToward(escort, forward)
    end
    self.focus = ship
    self.hideHud = true
    -- Orbit the lead (works like solo) with a pullback that fits the V.
    setPlateCamera(self, nil, 62, -1.0, 0.26)
    self.camFollow = ship

  elseif preset == 'skirmish' then
    -- Static two-wing tableau. Attack AI orbits out to pulseRange (~1000) and
    -- empties the frame — we aim/fire turrets ourselves during settle instead.
    local enemy = Entities.Player()
    insert(self.system.players, enemy)
    local origin = Config.gen.origin
    ship:setPos(origin + Vec3f(0, 8000, 0))

    local wingA, wingB = {}, {}
    refreshShipType(self.system)
    for i = 1, 5 do
      local z = (i - 3) * 12
      local y = ((i % 2) * 2 - 1) * 4
      local a = spawnOwnedShip(
        self.system, self.player, origin + Vec3f(-22, y, z), i > 1)
      faceToward(a, Vec3f(1, 0, 0))
      insert(wingA, a)
    end
    refreshShipType(self.system)
    for i = 1, 5 do
      local z = (i - 3) * 12
      local y = ((i % 2) * 2 - 1) * 4
      local b = spawnOwnedShip(
        self.system, enemy, origin + Vec3f(22, -y, z), i > 1)
      faceToward(b, Vec3f(-1, 0, 0))
      insert(wingB, b)
    end

    self.player:setControlling(wingA[3])
    self.focus = wingA[3]
    self.hideHud = true
    self.skirmishPairs = {}
    for i = 1, #wingA do
      insert(self.skirmishPairs, { from = wingA[i], at = wingB[i] })
      insert(self.skirmishPairs, { from = wingB[i], at = wingA[i] })
    end
    -- Midpoint plate — both columns stay readable.
    setPlateCamera(self, origin + Vec3f(0, 6, 0), 70, -1.25, 0.30)

  elseif preset == 'system' then
    -- Reminiscing vista: station, rocks, a few ships under the nebula.
    local station = self.system:spawnStation()
    self.system:spawnAsteroidField(60, 6)
    for i = 1, 5 do
      local offset = Vec3f(
        (i % 2 == 0 and 1 or -1) * (140 + 40 * i),
        20 * (i % 3 - 1),
        100 + 30 * i)
      local traffic = spawnOwnedShip(self.system, self.player, station:getPos() + offset, true)
      faceToward(traffic, Vec3f(0, 0, 1))
      traffic:pushAction(Actions.Escort(station, offset))
    end
    -- Park the player stub near the station for camera focus
    ship:setPos(station:getPos() + Vec3f(160, 40, -120))
    self.focus = station
    self.hideHud = true

  elseif preset == 'capital' then
    local origin = Config.gen.origin
    local forward = Vec3f(0, 0, 1)
    ship:setPos(origin)
    faceToward(ship, forward)
    self.focus = ship
    self.hideHud = true
    self.camFollow = ship
    setPlateCamera(self, nil, camRadiusFor(ship, 3.4, 160), -1.05, 0.22)

  elseif preset == 'armada' then
    -- Capital lead + fighter screen. Fighters use a larger scale so they
    -- still read when the camera is pulled back for the capital.
    local origin = Config.gen.origin
    local forward = Vec3f(0, 0, 1)
    ship:setPos(origin)
    faceToward(ship, forward)
    local rad = camRadiusFor(ship, 1.0, 50)
    local ring = math.max(40, rad * 1.08)
    bindShipType(self.system, 'fighter', 14)
    local slots = {
      Vec3f(-ring * 0.55,  rad * 0.08, -ring * 0.15),
      Vec3f( ring * 0.55, -rad * 0.05, -ring * 0.15),
      Vec3f(-ring * 0.9,   rad * 0.12, -ring * 0.45),
      Vec3f( ring * 0.9,   rad * 0.02, -ring * 0.45),
      Vec3f(-ring * 1.15,  rad * 0.05, -ring * 0.8),
      Vec3f( ring * 1.15, -rad * 0.08, -ring * 0.8),
      Vec3f( 0,            rad * 0.18, -ring * 0.3),
    }
    for i = 1, #slots do
      local escort = spawnOwnedShip(
        self.system, self.player, origin + slots[i], true)
      faceToward(escort, forward)
    end
    self.focus = ship
    self.hideHud = true
    self.camFollow = ship
    setPlateCamera(self, nil, camRadiusFor(ship, 2.9, 150), -0.95, 0.2)
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
  elseif self.camFollow or self.camCenter then
    -- Formation plates: follow an entity or orbit a world midpoint.
    if self.camFollow then
      cam:setTarget(self.camFollow)
    else
      cam:setTarget(nil)
      cam:setCenter(self.camCenter.x, self.camCenter.y, self.camCenter.z)
    end
    cam:setRadius(self.camRadius or 80)
    cam:setPitch(self.camPitch or 0.25)
    cam:setYaw(self.camYaw or -1.1)
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
    elseif preset == 'system' then
      cam:setRadius(700)
      cam:setPitch(0.28)
      cam:setYaw(-1.25)
    elseif preset == 'capital' or preset == 'armada' then
      cam:setRadius(self.camRadius or camRadiusFor(self.focus, 3.4, 160))
      cam:setPitch(self.camPitch or 0.22)
      cam:setYaw(self.camYaw or -1.05)
    else -- ship / solo
      cam:setRadius(preset == 'solo' and 22 or 28)
      cam:setPitch(0.28)
      cam:setYaw(-1.0)
    end
  end
  cam:warp()
end

function Wallpaper:resolveOutPath ()
  local o = self.opts
  local preset = o.preset
  local seedStr = seedToArg(self.seed)
  local idx = self.batchIndex or 1

  if o.outdir and o.outdir ~= '' then
    local dir = o.outdir:gsub('/+$', '')
    Directory.Create(dir)
    return string.format('%s/lt_%03d_%s_%s.png', dir, idx, preset, seedStr)
  end

  local out = o.out
  if not out or out == '' then
    Directory.Create('./wallpaper')
    if o.count > 1 then
      return string.format('./wallpaper/lt_%03d_%s_%s.png', idx, preset, seedStr)
    end
    return string.format('./wallpaper/lt_%s_%s.png', seedStr, preset)
  end

  if out:match('/$') then
    local dir = out:gsub('/+$', '')
    Directory.Create(dir)
    return string.format('%s/lt_%03d_%s_%s.png', dir, idx, preset, seedStr)
  end

  local dir = out:match('^(.+)/[^/]+$')
  if dir then Directory.Create(dir) end

  if o.count <= 1 then
    return out
  end

  local stem = out:gsub('%.png$', '')
  return string.format('%s_%03d.png', stem, idx)
end

function Wallpaper:capture ()
  local out = self:resolveOutPath()
  local tex = Tex2D.ScreenCapture()
  tex:save(out)
  tex:free()
  printf('Wallpaper written: %s  (%d/%d)', out, self.batchIndex or 1, self.opts.count)
  self.wrote = out
  if not self.wroteList then self.wroteList = {} end
  insert(self.wroteList, out)
end

function Wallpaper:settleFramesForPreset (preset)
  if self.opts.framesExplicit then
    return self.opts.frames
  end
  return DEFAULT_FRAMES[preset] or 4
end

function Wallpaper:selectBatchPlate ()
  local o = self.opts
  local idx = self.batchIndex
  if o.presets and #o.presets > 0 then
    o.preset = o.presets[((idx - 1) % #o.presets) + 1]
  end
  o.frames = self:settleFramesForPreset(o.preset)

  if idx == 1 then
    -- First plate uses the user-supplied seed (or time).
    return
  end
  -- Advance seed in-process so each plate differs without relaunching.
  if not self.batchSeedRng then
    self.batchSeedRng = RNG.Create(1 + (idx * 2654435761) % 2147483647):managed()
  end
  o.seed = seedToArg(self.batchSeedRng:get64())
end

function Wallpaper:beginPlate ()
  self:selectBatchPlate()
  self:generate()
  -- Batch plates are always HUD-free (wallpapers).
  if self.opts.count > 1 then
    self.hideHud = true
  end
  if self.gameView then
    self:applyCamera()
  end
  self.framesLeft = self.opts.frames
  self.plateDone = false
end

function Wallpaper:advanceOrQuit ()
  if self.batchIndex >= self.opts.count then
    printf('Wallpaper batch complete: %d plate(s)', self.opts.count)
    self:quit()
    return
  end
  self.batchIndex = self.batchIndex + 1
  printf('Wallpaper batch next: %d/%d', self.batchIndex, self.opts.count)
  self:beginPlate()
end

function Wallpaper:onInit ()
  self:ensureOpts()
  self.player = Entities.Player()
  self.batchIndex = 1
  self.wroteList = {}

  -- World first; GameView needs a controlling body from generate().
  self:beginPlate()
  do
    local n = tonumber(seedToArg(self.seed):sub(-9)) or 1
    self.batchSeedRng = RNG.Create(1 + (n % 2147483646)):managed()
  end

  DebugControl.ltheory = self
  self.gameView = GUI.GameView(self.player)
  self.canvas = UI.Canvas()
  if self.hideHud or self.skyOnly or self.opts.count > 1 then
    self.canvas:add(self.gameView)
  else
    self.canvas:add(self.gameView
      :add(Controls.MasterControl(self.gameView, self.player)))
  end

  self:applyCamera()
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
  -- Skirmish: hold the tableau and let turrets speak (no Attack AI drift).
  if self.skirmishPairs then
    for i = 1, #self.skirmishPairs do
      local pair = self.skirmishPairs[i]
      fireTurretsAt(pair.from, pair.at)
    end
  end

  self.player:getRoot():update(dt)
  self.canvas:update(dt)

  if not self.opts.interactive and not self.plateDone then
    self.framesLeft = self.framesLeft - 1
    if self.framesLeft <= 0 then
      self.plateDone = true
      self.doCapture = true
    end
  end
end

function Wallpaper:onDraw ()
  self.canvas:draw(self.resX, self.resY)
  if self.doCapture then
    self.doCapture = false
    self:capture()
    self:advanceOrQuit()
  end
end

return Wallpaper
