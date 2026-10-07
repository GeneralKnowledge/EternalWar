local Config = require('env.util.Config')

-- Distro LuaJIT (Ubuntu) often has version_num != 20100 expected by the
-- vendored script/jit/* modules. Load them softly so the app still runs.
local function tryRequire (name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
  return nil, mod
end

local jp = tryRequire('jit.p')
local jv = tryRequire('jit.v')
local jd = tryRequire('jit.dump2')
local bc = tryRequire('jit.bc')

local Jit = {}
local jitToolsOk = jp and jv and jd and bc

function Jit.GetBytecode (fn)
  if not bc then return '' end
  local lines = {}
  local target = bc.targets(fn)
  for pc = 1, 1000000000 do
    local s = bc.line(fn, pc, target[pc] and '=>')
    if not s then break end
    lines[#lines + 1] = s
  end
  return table.concat(lines, '')
end

function Jit.StartDump ()
  if not jd then return end
  jd.on('timT', 'log/jd.txt')
end

function Jit.StartProfile ()
  if not jp then return end
  if Config.jit.profileVM then
    jp.start('fv2', 'log/jp.txt')
  else
    jp.start('vzF2i1', 'log/jp.txt')
  end
end

function Jit.StartVerbose ()
  if not jv then return end
  jv.on('log/jv.txt')
end

function Jit.StopDump ()
  if jd then jd.off() end
end

function Jit.StopProfile ()
  if jp then jp.stop() end
end

function Jit.StopVerbose ()
  if jv then jv.off() end
end

function Jit.ToolsAvailable ()
  return jitToolsOk == true
end

return Jit
