local Entity = require('Game.Entity')
local Material = require('Game.Material')

local Station = subclass(Entity, function (self, seed)
  -- Wallpaper can request ShapeLib stations via Config.gen.stationMesh = 'shape'
  local mesh
  if Config.gen.stationMesh == 'shape' then
    mesh = Gen.Station.GenerateStation(seed):managed()
  else
    mesh = Gen.StationOld(seed):managed()
  end
  self:addActions()
  self:addCapacitor(10000, 10000, 100)
  self:addChildren()
  self:addDockable()
  self:addFlows()
  self:addHealth(10000, 10000, 0)
  self:addInventory(1e10)
  self:addRigidBody(true, mesh)
  self:addVisibleMesh(mesh, Material.Metal())

  self:setDrag(0, 0)
  self:setScale(100)
  self:setMass(1e10)
end)

return Station
