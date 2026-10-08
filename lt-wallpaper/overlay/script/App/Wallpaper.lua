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
    preset=<name>       sky | nebula | ship | solo | asteroids | planet | belt |
                        station | fleet | skirmish | system | vista | capital |
                        armada | mining | aftermath
    presets=<a,b,...>   Cycle these presets across the batch (overrides preset)
    count=<int>         Captures before quit; process stays loaded (default 1)
    frames=<int>        Settle frames before capture (default depends on preset)
    interactive=1       Keep window; F12 capture, R regen, Esc quit
    nebulaRes=<int>     Override Config.gen.nebulaRes
    nebulaStyle=ifs|lt  Force IFS (Nebula1) or light-transport (Nebula2) sky
    hull=sausage|triangle|top|auto   Capital hull family
    fighter=standard|surreal|auto           Fighter generator
    thrusters=0|1       Engine glow on ships (default 1)
    superSample=1|2|4   Export supersample (default 2)
    seed=good           Pick from Josh's curated goodSeeds list

  Wrapper-only (tools/wallpaper.sh / wallpaperd.py):
    best=<int>          Bake N candidates in one launch; keep the highest-scoring PNG
    daemon=1 spool=DIR  Stay loaded; pull jobs from DIR/job.req (warm daemon)
]]

local Entities = requireAll('Game.Entities')
local Actions = requireAll('Game.Actions')
local DebugControl = require('Game.Controls.DebugControl')
local ShipFighter = require('Gen.ShipFighter')
local ShipCapital = require('Gen.ShipCapital')

local Wallpaper = Application()
Wallpaper.opts = nil

local PRESETS = {
  sky = true,
  nebula = true,   -- alias → sky
  ship = true,     -- fighter + asteroid field
  solo = true,     -- fighter only
  asteroids = true,
  planet = true,
  belt = true,     -- planet + asteroid belt ring
  station = true,  -- ShapeLib station + traffic
  fleet = true,    -- lead ship + escorts
  skirmish = true, -- two sides mid-fight
  system = true,   -- station + rocks + ships
  vista = true,    -- LTheory-lite: station + field + static escort cloud
  capital = true,  -- Gen.ShipCapital (hull variants)
  armada = true,   -- capital + fighter screen
  mining = true,   -- ore rocks + posed miners
  aftermath = true,-- mid-explosion still after a clash
}

local DEFAULT_FRAMES = {
  sky = 4,
  nebula = 4,
  ship = 4,
  solo = 4,
  asteroids = 4,
  planet = 5,
  belt = 5,
  station = 6,
  fleet = 4,
  -- Turret volleys need a few frames for pulses to be in-flight; no Attack AI.
  skirmish = 10,
  system = 10,
  vista = 6,
  capital = 5,
  armada = 5,
  mining = 5,
  aftermath = 8,
}

-- Josh's curated sky seeds from Config.App.lua (digit form for CLI).
local GOOD_SEEDS = {
  '14589938814258111262',
  '15297218883250103974',
  '1842258441393851360',
  '1305797465843153519',
  '5421862249219039751',
  '638780708004697442',
}

local CAPITAL_SCALE = 48
local FIGHTER_SCALE = 4
-- Burger references missing ShipCapital.Plate — skip it.
local CAPITAL_HULLS = {
  sausage = ShipCapital.Sausage,
  triangle = ShipCapital.Triangle,
  top = ShipCapital.Top,
}
local CAPITAL_HULL_NAMES = { 'sausage', 'triangle', 'top' }

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

local function applyOptKV (opts, k, v)
  if k == 'seed' then
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
  elseif k == 'nebulaStyle' or k == 'nebula' then
    -- ifs | lt | auto (also accept nebula1 / nebula2 aliases)
    if v == 'nebula1' then v = 'ifs' end
    if v == 'nebula2' then v = 'lt' end
    opts.nebulaStyle = v
  elseif k == 'hull' then
    opts.hull = v
  elseif k == 'fighter' then
    opts.fighter = v
  elseif k == 'thrusters' then
    opts.thrusters = (v ~= '0' and v ~= 'false' and v ~= 'no')
  elseif k == 'superSample' or k == 'ss' then
    opts.superSample = tonumber(v)
  elseif k == 'daemon' then
    opts.daemon = (v == '1' or v == 'true' or v == 'yes')
  elseif k == 'spool' then
    opts.spool = v
  elseif k == 'id' then
    opts.jobId = v
  else
    return false
  end
  return true
end

local function finalizeOpts (opts)
  if opts.presets and #opts.presets > 0 then
    opts.preset = opts.presets[1]
  elseif not PRESETS[opts.preset] then
    printf('Wallpaper: unknown preset <%s>, using ship', tostring(opts.preset))
    opts.preset = 'ship'
  end
  if not opts.frames then
    opts.frames = DEFAULT_FRAMES[opts.preset] or 4
  end
  if opts.count > 1 or opts.daemon then
    opts.interactive = false
  end
  if opts.daemon and (not opts.spool or opts.spool == '') then
    opts.spool = './wallpaper/spool'
  end
  return opts
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
    nebulaStyle = 'auto',
    hull = 'auto',
    fighter = 'auto',
    thrusters = true,
    superSample = 2,
    daemon = false,
    spool = nil,
    jobId = nil,
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
    elseif not applyOptKV(opts, k, v) then
      printf('Wallpaper: ignoring unrecognized flag <%s>', k)
    end
  end
  if opts.seed == 'good' or opts.seed == 'curated' then
    local idx = 1 + (os.time() % #GOOD_SEEDS)
    opts.seed = GOOD_SEEDS[idx]
    printf('Wallpaper: using curated goodSeed[%d]=%s', idx, opts.seed)
  end
  return finalizeOpts(opts)
end

local function spoolPath (spool, name)
  return (spool:gsub('/+$', '')) .. '/' .. name
end

local function writeText (path, body)
  local f, err = io.open(path, 'w')
  if not f then
    printf('Wallpaper: failed to write %s (%s)', path, tostring(err))
    return false
  end
  f:write(body)
  f:close()
  return true
end

local function readText (path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local body = f:read('*a')
  f:close()
  return body
end

local function fileExists (path)
  local f = io.open(path, 'r')
  if not f then return false end
  f:close()
  return true
end

local function parseJobBody (body)
  local opts = {
    seed = nil,
    width = nil,
    height = nil,
    out = nil,
    outdir = nil,
    preset = 'ship',
    presets = nil,
    count = 1,
    frames = nil,
    framesExplicit = false,
    interactive = false,
    nebulaRes = nil,
    nebulaStyle = 'auto',
    hull = 'auto',
    fighter = 'auto',
    thrusters = true,
    superSample = 2,
    jobId = nil,
  }
  for line in string.gmatch(body, '[^\r\n]+') do
    local k, v = line:match('^([%w_]+)=(.*)$')
    if k then applyOptKV(opts, k, v) end
  end
  if opts.seed == 'good' or opts.seed == 'curated' then
    local idx = 1 + (os.time() % #GOOD_SEEDS)
    opts.seed = GOOD_SEEDS[idx]
  end
  return finalizeOpts(opts)
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

local function wrapRngGen (fn)
  return function (seed, _res)
    return fn(RNG.Create(seed))
  end
end

local function pickCapitalHull (opts, rng)
  local name = opts.hull or 'auto'
  if name == 'auto' or not CAPITAL_HULLS[name] then
    name = CAPITAL_HULL_NAMES[1 + rng:getInt(0, #CAPITAL_HULL_NAMES - 1)]
  end
  return name, CAPITAL_HULLS[name]
end

local function pickFighterGen (opts, rng)
  local name = opts.fighter or 'auto'
  if name == 'auto' then
    -- Bias Standard; Surreal ~30% for silhouette variety.
    name = rng:chance(0.30) and 'surreal' or 'standard'
  end
  if name == 'surreal' then
    return name, wrapRngGen(ShipFighter.Surreal)
  end
  return 'standard', wrapRngGen(ShipFighter.Standard)
end

--- Force a fresh ShapeLib hull on the next System:spawnShip().
local function refreshShipType (system)
  system.shipType = nil
end

--- Bind fighter or capital generator before spawnShip().
local function bindShipType (system, kind, scale, opts)
  opts = opts or {}
  local scl = scale or FIGHTER_SCALE
  local gen
  if kind == 'capital' then
    local _name, hullFn = pickCapitalHull(opts, system.rng)
    gen = wrapRngGen(hullFn)
    scl = scale or CAPITAL_SCALE
  else
    local _name, fighterFn = pickFighterGen(opts, system.rng)
    gen = fighterFn
    scl = scale or FIGHTER_SCALE
  end
  system.shipType = ShipType(system.rng:get31(), gen, scl)
end

local function faceToward (entity, forward)
  entity:setRot(Quat.FromLookUp(forward:normalize(), Vec3f(0, 1, 0)))
end

local function igniteThrusters (ship, amount, boost)
  if not ship or not ship.hasSockets or not ship:hasSockets() then return end
  amount = amount or 0.9
  boost = boost or 0.4
  for thruster in ship:iterSocketsByType(SocketType.Thruster) do
    thruster.activationT = amount
    thruster.activation = amount
    thruster.boostT = boost
    thruster.boost = boost
  end
end

local function igniteAllShips (system, amount, boost)
  for _, child in system:iterChildren() do
    if child.hasSockets and child:hasSockets() then
      igniteThrusters(child, amount, boost)
    end
  end
end

--- Planetary belt rocks around a planet (from SystemBasic geometry).
local function spawnPlanetBelt (system, planet, count)
  local rng = system.rng
  local center = planet:getPos()
  local rc = 2.00 * planet:getRadius()
  local rw = 0.20 * planet:getRadius()
  for _ = 1, count do
    local r = rc + rng:getUniformRange(-rw, rw) * (0.5 + 0.5 * rng:getExp())
    local h = 0.1 * rw * rng:getGaussian()
    local dir = rng:getDir2()
    local scale = 5.0 * (1.0 + rng:getExp() ^ 2.0)
    local rock = Entities.Asteroid(rng:get31(), scale)
    rock:setPos(center + Vec3f(r * dir.x, h, r * dir.y))
    rock:setRot(rng:getQuat())
    rock:setScale(scale)
    system:addChild(rock)
  end
end

--- Spawn a ship. reuseType=true keeps the current ShapeLib hull (fleet cohesion).
--- kind: nil/'fighter'/'capital' — ignored when reuseType is true.
local function spawnOwnedShip (system, owner, pos, reuseType, kind, scale, opts)
  if not reuseType then
    bindShipType(
      system,
      kind == 'capital' and 'capital' or 'fighter',
      scale,
      opts or {})
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
  local opts = self.opts
  printf('Wallpaper seed: %s  preset: %s  size: %dx%d',
    tostring(seed), preset, opts.width, opts.height)

  if opts.nebulaRes then
    Config.gen.nebulaRes = opts.nebulaRes
  end
  if opts.nebulaStyle and opts.nebulaStyle ~= 'auto' then
    Config.gen.nebulaStyle = opts.nebulaStyle
  else
    Config.gen.nebulaStyle = nil
  end
  -- ShapeLib stations for wallpaper plates (StationOld remains for vanilla).
  Config.gen.stationMesh = 'shape'

  Config.debug.metrics = false
  Config.render.vsync = false

  -- Enum indices: 1=Off, 2=2x, 3=4x
  local ss = opts.superSample or 2
  if ss >= 4 then
    Settings.set('render.superSample', 3)
  elseif ss >= 2 then
    Settings.set('render.superSample', 2)
  else
    Settings.set('render.superSample', 1)
  end
  Settings.set('postfx.vignette.enable', true)
  Settings.set('postfx.vignette.strength', 0.28)
  Settings.set('postfx.vignette.hardness', 18.0)

  if self.system then self.system:delete() end
  self.system = Entities.System(seed)
  local rng = self.system.rng

  -- Controlling body (required by GameView). Capitals use Gen.ShipCapital.
  local startKind = 'fighter'
  if preset == 'capital' or preset == 'armada' then
    startKind = 'capital'
  end
  local ship = spawnOwnedShip(
    self.system, self.player, Config.gen.origin, false, startKind, nil, opts)
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

  elseif preset == 'planet' or preset == 'belt' then
    self.system:spawnPlanet()
    local planet
    for _, child in self.system:iterChildren() do
      if child ~= ship and child.getScale then
        local ok, scale = pcall(function () return child:getScale() end)
        if ok and scale and scale > 1000 then
          planet = child
          self.focus = child
          break
        end
      end
    end
    if planet and preset == 'belt' then
      spawnPlanetBelt(self.system, planet, 48)
    end

  elseif preset == 'station' then
    local station = self.system:spawnStation()
    if station.addLight then station:addLight(1.0, 0.82, 0.55) end
    self.focus = station
    self.hideHud = true
    -- Light traffic around the station (local offsets for Escort)
    for i = 1, 4 do
      local offset = Vec3f(
        (i % 2 == 0 and 1 or -1) * (90 + 35 * i),
        10 * (i - 2),
        70 + 20 * i)
      local traffic = spawnOwnedShip(
        self.system, self.player, station:getPos() + offset, true, nil, nil, opts)
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
      local escort = spawnOwnedShip(
        self.system, self.player, origin + slots[i], true, nil, nil, opts)
      faceToward(escort, forward)
    end
    self.focus = ship
    self.hideHud = true
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
    for i = 1, 5 do
      local z = (i - 3) * 12
      local y = ((i % 2) * 2 - 1) * 4
      local a = spawnOwnedShip(
        self.system, self.player, origin + Vec3f(-22, y, z), i > 1, 'fighter', nil, opts)
      faceToward(a, Vec3f(1, 0, 0))
      insert(wingA, a)
    end
    refreshShipType(self.system)
    for i = 1, 5 do
      local z = (i - 3) * 12
      local y = ((i % 2) * 2 - 1) * 4
      local b = spawnOwnedShip(
        self.system, enemy, origin + Vec3f(22, -y, z), i > 1, 'fighter', nil, opts)
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
    setPlateCamera(self, origin + Vec3f(0, 6, 0), 70, -1.25, 0.30)

  elseif preset == 'system' then
    local station = self.system:spawnStation()
    if station.addLight then station:addLight(1.0, 0.82, 0.55) end
    self.system:spawnAsteroidField(60, 6)
    for i = 1, 5 do
      local offset = Vec3f(
        (i % 2 == 0 and 1 or -1) * (140 + 40 * i),
        20 * (i % 3 - 1),
        100 + 30 * i)
      local traffic = spawnOwnedShip(
        self.system, self.player, station:getPos() + offset, true, nil, nil, opts)
      faceToward(traffic, Vec3f(0, 0, 1))
      traffic:pushAction(Actions.Escort(station, offset))
    end
    ship:setPos(station:getPos() + Vec3f(160, 40, -120))
    self.focus = station
    self.hideHud = true

  elseif preset == 'vista' then
    -- LTheory-lite: station + field + static escort cloud (no Escort AI drift).
    local station = self.system:spawnStation()
    if station.addLight then station:addLight(1.0, 0.85, 0.6) end
    self.system:spawnAsteroidField(90, 8)
    local origin = station:getPos()
    ship:setPos(origin + Vec3f(180, 50, -140))
    faceToward(ship, Vec3f(0, 0, 1))
    local slots = {
      Vec3f(120,  30, -80), Vec3f(220, -20, -60), Vec3f(160,  10,  40),
      Vec3f(280,  40, -120), Vec3f(90, -30, -160), Vec3f(240,  60,  20),
      Vec3f(200, -40, -200), Vec3f(140,  70, -40), Vec3f(300,  20, -40),
      Vec3f(100,  0,  80), Vec3f(260, -50, -90), Vec3f(180,  40, -220),
      Vec3f(320,  10, -150), Vec3f(70,  50, -100), Vec3f(210, -10,  90),
      Vec3f(150, -60, -30), Vec3f(290,  35,  50), Vec3f(110,  25, -240),
    }
    for i = 1, #slots do
      local escort = spawnOwnedShip(
        self.system, self.player, origin + slots[i], i > 1, 'fighter', nil, opts)
      faceToward(escort, Vec3f(0.2, 0, 1))
    end
    self.focus = station
    self.hideHud = true
    setPlateCamera(self, origin + Vec3f(40, 80, -40), 520, -1.15, 0.32)

  elseif preset == 'mining' then
    self.system:spawnAsteroidField(50, 18)
    local origin = Config.gen.origin
    ship:setPos(origin)
    faceToward(ship, Vec3f(0.4, 0, 1))
    -- Pose a few miners near denser rocks around origin.
    local minerSlots = {
      Vec3f(35, 8, -20), Vec3f(-40, -6, 15), Vec3f(10, 12, 40),
      Vec3f(-25, 4, -45),
    }
    for i = 1, #minerSlots do
      local miner = spawnOwnedShip(
        self.system, self.player, origin + minerSlots[i], true, nil, nil, opts)
      faceToward(miner, Vec3f(-minerSlots[i].x, 0, -minerSlots[i].z) + Vec3f(0, 0, 0.2))
    end
    self.focus = ship
    self.hideHud = true
    setPlateCamera(self, origin + Vec3f(0, 20, 0), 95, -0.95, 0.34)

  elseif preset == 'aftermath' then
    -- Mid-explosion still: two wings held, pulses + blast billboards mid-age.
    local enemy = Entities.Player()
    insert(self.system.players, enemy)
    local origin = Config.gen.origin
    ship:setPos(origin + Vec3f(0, 8000, 0))
    local wingA, wingB = {}, {}
    for i = 1, 4 do
      local a = spawnOwnedShip(
        self.system, self.player, origin + Vec3f(-18, (i - 2) * 6, (i - 2) * 8),
        i > 1, 'fighter', nil, opts)
      faceToward(a, Vec3f(1, 0, 0))
      insert(wingA, a)
    end
    refreshShipType(self.system)
    for i = 1, 4 do
      local b = spawnOwnedShip(
        self.system, enemy, origin + Vec3f(18, (i - 2) * -5, (i - 2) * 8),
        i > 1, 'fighter', nil, opts)
      faceToward(b, Vec3f(-1, 0, 0))
      insert(wingB, b)
    end
    self.player:setControlling(wingA[2])
    self.focus = wingA[2]
    self.hideHud = true
    self.skirmishPairs = {}
    for i = 1, math.min(#wingA, #wingB) do
      insert(self.skirmishPairs, { from = wingA[i], at = wingB[i] })
      insert(self.skirmishPairs, { from = wingB[i], at = wingA[i] })
    end
    for i = 1, 6 do
      local pos = origin + Vec3f(
        rng:getUniformRange(-12, 12),
        rng:getUniformRange(-4, 10),
        rng:getUniformRange(-10, 10))
      local boom = Entities.Explosion(pos)
      boom.age = 0.55 + 0.2 * i
      self.system:addChild(boom)
    end
    setPlateCamera(self, origin + Vec3f(0, 8, 0), 72, -1.2, 0.28)

  elseif preset == 'capital' then
    local origin = Config.gen.origin
    local forward = Vec3f(0, 0, 1)
    ship:setPos(origin)
    faceToward(ship, forward)
    if ship.addLight then ship:addLight(0.35, 0.55, 1.1) end
    self.focus = ship
    self.hideHud = true
    self.camFollow = ship
    setPlateCamera(self, nil, camRadiusFor(ship, 3.4, 160), -1.05, 0.22)

  elseif preset == 'armada' then
    local origin = Config.gen.origin
    local forward = Vec3f(0, 0, 1)
    ship:setPos(origin)
    faceToward(ship, forward)
    if ship.addLight then ship:addLight(0.35, 0.55, 1.1) end
    local rad = camRadiusFor(ship, 1.0, 50)
    local ring = math.max(40, rad * 1.08)
    bindShipType(self.system, 'fighter', 14, opts)
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
        self.system, self.player, origin + slots[i], true, nil, nil, opts)
      faceToward(escort, forward)
    end
    self.focus = ship
    self.hideHud = true
    self.camFollow = ship
    setPlateCamera(self, nil, camRadiusFor(ship, 2.9, 150), -0.95, 0.2)
  end

  if opts.thrusters ~= false and not self.skyOnly then
    igniteAllShips(self.system, 0.92, 0.45)
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
    elseif preset == 'planet' or preset == 'belt' then
      cam:setRadius(self.focus.getScale and (self.focus:getScale() * 3.5) or 8000)
      cam:setPitch(0.25)
      cam:setYaw(-Math.Pi2)
    elseif preset == 'station' then
      cam:setRadius(420)
      cam:setPitch(0.32)
      cam:setYaw(-0.95)
    elseif preset == 'system' or preset == 'vista' then
      cam:setRadius(self.camRadius or (preset == 'vista' and 520 or 700))
      cam:setPitch(self.camPitch or 0.28)
      cam:setYaw(self.camYaw or -1.25)
    elseif preset == 'mining' or preset == 'aftermath' then
      cam:setRadius(self.camRadius or 90)
      cam:setPitch(self.camPitch or 0.32)
      cam:setYaw(self.camYaw or -1.0)
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

function Wallpaper:daemonSetReady (ready)
  local spool = self.opts.spool
  if not spool then return end
  local readyPath = spoolPath(spool, 'daemon.ready')
  if ready then
    writeText(readyPath, '1\n')
  elseif fileExists(readyPath) then
    os.remove(readyPath)
  end
end

function Wallpaper:daemonWriteDone (ok, err)
  local spool = self.opts.spool
  local id = self.opts.jobId or 'job'
  local lines = { 'id=' .. id, ok and 'ok=1' or 'ok=0' }
  if err then
    insert(lines, 'error=' .. tostring(err):gsub('\n', ' '))
  end
  local list = self.wroteList or {}
  insert(lines, 'count=' .. tostring(#list))
  for i = 1, #list do
    insert(lines, string.format('path%d=%s', i - 1, list[i]))
  end
  -- Atomic-ish: write .tmp then rename via second write to job.done
  local tmp = spoolPath(spool, 'job.done.tmp')
  local done = spoolPath(spool, 'job.done')
  writeText(tmp, table.concat(lines, '\n') .. '\n')
  os.rename(tmp, done)
  local req = spoolPath(spool, 'job.req')
  if fileExists(req) then os.remove(req) end
end

function Wallpaper:daemonParkIdle ()
  -- Cheap sky park so heavy capital meshes can be released between jobs.
  self.opts.preset = 'sky'
  self.opts.count = 1
  self.opts.out = nil
  self.opts.outdir = nil
  self.opts.presets = nil
  self.opts.frames = 2
  self.opts.framesExplicit = true
  self.skirmishPairs = nil
  self.camFollow = nil
  self.camCenter = nil
  self:generate()
  if self.gameView then self:applyCamera() end
  self.daemonIdle = true
  self.plateDone = true
  self.doCapture = false
  self:daemonSetReady(true)
  printf('Wallpaper daemon idle — waiting for jobs in %s', self.opts.spool)
end

function Wallpaper:daemonAcceptJob (job)
  self:daemonSetReady(false)
  -- Merge job into live opts (keep spool/daemon flags).
  local spool = self.opts.spool
  self.opts.seed = job.seed
  self.opts.preset = job.preset
  self.opts.presets = job.presets
  self.opts.count = job.count or 1
  self.opts.out = job.out
  self.opts.outdir = job.outdir
  self.opts.nebulaRes = job.nebulaRes
  self.opts.nebulaStyle = job.nebulaStyle or self.opts.nebulaStyle
  self.opts.hull = job.hull or self.opts.hull
  self.opts.fighter = job.fighter or self.opts.fighter
  if job.thrusters ~= nil then self.opts.thrusters = job.thrusters end
  if job.superSample ~= nil then self.opts.superSample = job.superSample end
  self.opts.jobId = job.jobId
  self.opts.frames = job.frames
  self.opts.framesExplicit = job.framesExplicit
  if not self.opts.framesExplicit then
    self.opts.frames = self:settleFramesForPreset(self.opts.preset)
  end
  self.opts.spool = spool
  self.opts.daemon = true
  self.opts.interactive = false

  local w = job.width or self.opts.width
  local h = job.height or self.opts.height
  if w and h and self.window and (w ~= self.resX or h ~= self.resY) then
    self.opts.width = w
    self.opts.height = h
    self.window:setSize(w, h)
  end

  self.batchIndex = 1
  self.wroteList = {}
  self.daemonIdle = false
  do
    local seedIn = self.opts.seed
    if seedIn == '' then seedIn = nil end
    local n = tonumber(seedToArg(parseSeed(seedIn)):sub(-9)) or 1
    self.batchSeedRng = RNG.Create(1 + (n % 2147483646)):managed()
  end
  printf('Wallpaper daemon job %s — preset=%s count=%d',
    tostring(self.opts.jobId), self.opts.preset, self.opts.count)
  self:beginPlate()
end

function Wallpaper:daemonPoll ()
  local spool = self.opts.spool
  if fileExists(spoolPath(spool, 'shutdown')) then
    printf('Wallpaper daemon shutdown requested')
    self:quit()
    return
  end
  local req = spoolPath(spool, 'job.req')
  if not fileExists(req) then return end
  local body = readText(req)
  if not body or body == '' then return end
  -- Remove stale done from a previous client.
  local done = spoolPath(spool, 'job.done')
  if fileExists(done) then os.remove(done) end
  local ok, jobOrErr = pcall(parseJobBody, body)
  if not ok then
    self:daemonWriteDone(false, jobOrErr)
    self:daemonSetReady(true)
    return
  end
  local jobOk, err = pcall(function ()
    self:daemonAcceptJob(jobOrErr)
  end)
  if not jobOk then
    printf('Wallpaper daemon job failed to start: %s', tostring(err))
    self:daemonWriteDone(false, err)
    self:daemonParkIdle()
  end
end

function Wallpaper:advanceOrQuit ()
  if self.batchIndex >= self.opts.count then
    printf('Wallpaper batch complete: %d plate(s)', self.opts.count)
    if self.opts.daemon then
      self:daemonWriteDone(true)
      self:daemonParkIdle()
      return
    end
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
  self.daemonIdle = false

  if self.opts.daemon then
    Directory.Create(self.opts.spool)
    writeText(spoolPath(self.opts.spool, 'daemon.pid'), tostring(os.time()) .. '\n')
    -- Seed a parked sky world so GameView has a controlling body.
    self.opts.preset = 'sky'
    self.opts.count = 1
    self.opts.frames = 2
    self.opts.framesExplicit = true
    self:generate()
  else
    self:beginPlate()
    do
      local n = tonumber(seedToArg(self.seed):sub(-9)) or 1
      self.batchSeedRng = RNG.Create(1 + (n % 2147483646)):managed()
    end
  end

  DebugControl.ltheory = self
  self.gameView = GUI.GameView(self.player)
  self.canvas = UI.Canvas()
  if self.hideHud or self.skyOnly or self.opts.count > 1 or self.opts.daemon then
    self.canvas:add(self.gameView)
  else
    self.canvas:add(self.gameView
      :add(Controls.MasterControl(self.gameView, self.player)))
  end

  self:applyCamera()
  self.wrote = nil

  if self.opts.daemon then
    self:daemonParkIdle()
  end
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
  if self.opts.daemon and self.daemonIdle then
    self.daemonPollAcc = (self.daemonPollAcc or 0) + 1
    if self.daemonPollAcc >= 8 then
      self.daemonPollAcc = 0
      self:daemonPoll()
    end
  end

  -- Skirmish: hold the tableau and let turrets speak (no Attack AI drift).
  if self.skirmishPairs and not self.daemonIdle then
    for i = 1, #self.skirmishPairs do
      local pair = self.skirmishPairs[i]
      fireTurretsAt(pair.from, pair.at)
    end
  end

  if self.player and self.player.getRoot then
    local root = self.player:getRoot()
    if root then root:update(dt) end
  end
  if self.canvas then self.canvas:update(dt) end

  if not self.opts.interactive and not self.daemonIdle and not self.plateDone then
    self.framesLeft = self.framesLeft - 1
    if self.framesLeft <= 0 then
      self.plateDone = true
      self.doCapture = true
    end
  end
end

function Wallpaper:onDraw ()
  if self.canvas then
    self.canvas:draw(self.resX, self.resY)
  end
  if self.doCapture then
    self.doCapture = false
    self:capture()
    self:advanceOrQuit()
  end
end

return Wallpaper
