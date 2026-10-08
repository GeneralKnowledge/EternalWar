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
  self.envMap = bake(rng, Config.gen.nebulaRes, self.starDir):managed()
  self.irMap = self.envMap:genIRMap(256):managed()
  self.stars = Gen.Starfield(rng, Config.gen.nStars(rng)):managed()
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
