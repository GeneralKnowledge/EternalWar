local Nebula = class(function (self, seed, starDir)
  self.seed = seed
  self.starDir = starDir
end)

-- Bake functions registered by Gen.Nebula.*; also returned for style forcing.
local bakeIFS = require('Gen.Nebula.Nebula1')
local bakeLT  = require('Gen.Nebula.Nebula2')

function Nebula:forceLoad ()
  if self.envMap then return end
  local rng = RNG.Create(self.seed + 0xC0104FULL):managed()
  local style = Config.gen.nebulaStyle
  local bake
  if style == 'ifs' or style == 'nebula1' then
    bake = bakeIFS
  elseif style == 'lt' or style == 'nebula2' then
    bake = bakeLT
  else
    bake = Gen.Generator.Get('Nebula', rng)
  end

  local t0 = TimeStamp.Get()
  local res = Config.gen.nebulaRes
  self.envMap = bake(rng, res, self.starDir):managed()
  -- genIRMap(n) is GGX *sample count* per texel (not resolution). Upstream
  -- hardcodes 256 — the dominant software-GL cost after the IFS cubemap bake.
  -- Wallpaper sets Config.gen.irMapSamples lower; visual change is tiny on stills.
  local irSamples = Config.gen.irMapSamples or 256
  local t1 = TimeStamp.Get()
  self.irMap = self.envMap:genIRMap(irSamples):managed()
  self.stars = Gen.Starfield(rng, Config.gen.nStars(rng)):managed()
  if Config.gen.wallpaperTiming then
    printf(
      'Wallpaper timing: nebula IFS=%.2fs IR(samples=%s)=%.2fs total=%.2fs res=%s',
      TimeStamp.GetDifference(t0, t1),
      tostring(irSamples),
      TimeStamp.GetElapsed(t1),
      TimeStamp.GetElapsed(t0),
      tostring(res))
  end
end

function Nebula:render (state)
  self:forceLoad()
  if state.mode == BlendMode.Disabled then
    RenderState.PushDepthWritable(false)
    local shader = Cache.Shader('farplane', 'skybox')
    CullFace.Push(CullFace.None)
    shader:start()
    Draw.Box3(Box3f(-1, -1, -1, 1, 1, 1))
    shader:stop()
    CullFace.Pop()
    RenderState.PopDepthWritable()
  elseif state.mode == BlendMode.Additive then
    local shader = Cache.Shader('farplane', 'starbg')
    shader:start()
    Shader.SetTexCube('irMap', self.irMap)
    Shader.SetTexCube('envMap', self.envMap)
    self.stars:draw()
    shader:stop()
  end
end

return Nebula
