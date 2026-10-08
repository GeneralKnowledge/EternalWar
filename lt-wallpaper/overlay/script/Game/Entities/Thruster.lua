local Entity = require('Game.Entity')

-- Wallpaper overlay: larger, hotter plumes so engines read at plate distance.
-- Upstream thruster jets are 2×32 and easily lost against IFS nebulae.

local mesh
local meshJet
local rng = RNG.FromTime()

local Thruster
Thruster = subclass(Entity, function (self)
  if not mesh then
    mesh = Gen.ShipFighter.EngineSingle(rng)
    mesh:computeNormals()
    mesh:computeAO(0.1)
    meshJet = Gen.Primitive.Billboard(-1, 0, 1, 1)
  end

  self:addRigidBody(true, mesh)
  self:addVisibleMesh(mesh, Material.Debug())

  self.activation = 0
  self.activationT = 0
  self.boost = 0
  self.boostT = 0
  self.time = rng:getUniformRange(0, 1000)

  self:register(Event.Render, Thruster.render)
  self:register(Event.Update, Thruster.update)
end)

function Thruster:getSocketType ()
  return SocketType.Thruster
end

function Thruster:render (state)
  if state.mode == BlendMode.Additive then
    local a = math.abs(self.activation)
    if a < 1e-3 then return end
    local shader = Cache.Shader('billboard/axis', 'effect/thruster')
    shader:start()
    Shader.SetFloat('alpha', math.min(1.6, a * 1.35))
    Shader.SetFloat('time', self.time)
    -- Readable at plate distance without streaking across the whole frame.
    -- Upstream was 2 × 32*activation.
    local scale = self.getScale and self:getScale() or 1
    local length = math.max(14.0, 8.0 * scale) * self.activation
    local width = math.max(2.2, 1.1 * scale)
    Shader.SetFloat2('size', width, length)
    Shader.SetFloat3(
      'color',
      0.15 + 1.4 * self.boost,
      0.35 + 0.35 * self.boost,
      1.0 - 0.75 * self.boost)
    Shader.SetMatrix('mWorld', self:getToWorldMatrix())
    meshJet:draw()
    shader:stop()
  end
end

function Thruster:update (state)
  local t = 1.0 - exp(-4.0 * state.dt)
  self.activation = Math.Lerp(self.activation, self.activationT, t)
  self.boost = Math.Lerp(self.boost, self.boostT, t)
  self.time = self.time + state.dt
end

return Thruster
