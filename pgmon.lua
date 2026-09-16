--[[ pgmon - painel de monitoramento do PowerGrid
     Uso:  pgmon            usa o primeiro monitor encontrado (ou a tela do PC)
           pgmon 0.5        forca a escala de texto do monitor
     Teclas: Q sai . R re-varre os perifericos . G alterna o grafico
]]

local function loadLib(name)
  local ok, lib = pcall(require, name)
  if ok and type(lib) == "table" then return lib end
  local dir = fs.getDir(shell.getRunningProgram())
  local p = fs.combine(dir, name .. ".lua")
  if fs.exists(p) then return dofile(p) end
  error("Falta a biblioteca " .. name .. ".lua (coloque na mesma pasta)", 0)
end

local pgapi = loadLib("pgapi")

local REFRESH  = 0.5   -- segundos entre leituras
local HIST_MAX = 300   -- amostras guardadas do historico de potencia

-- ------------------------------------------------------------------- display

local args = { ... }
local scan = pgapi.scan()

local out, isMonitor
if #scan.monitor > 0 then
  out, isMonitor = scan.monitor[1].dev, true
  pcall(out.setTextScale, tonumber(args[1]) or 0.5)
else
  out, isMonitor = term.current(), false
end

local color = out.isColour and out.isColour()
local W, H = out.getSize()
-- buffer fora de tela: desenha tudo e so entao mostra, sem piscar
local buf = window.create(out, 1, 1, W, H, false)

local C
if color then
  C = { bg = colors.black, fg = colors.white, dim = colors.gray, title = colors.cyan,
        ok = colors.lime, warn = colors.orange, bad = colors.red,
        accent = colors.yellow, bar = colors.gray }
else
  C = { bg = colors.black, fg = colors.white, dim = colors.white, title = colors.white,
        ok = colors.white, warn = colors.white, bad = colors.white,
        accent = colors.white, bar = colors.black }
end

local function paint(fg, bg)
  buf.setTextColor(fg or C.fg)
  buf.setBackgroundColor(bg or C.bg)
end

--- Escreve truncando na largura disponivel.
local function writeAt(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  paint(fg, bg)
  buf.setCursorPos(x, y)
  buf.write(string.sub(s, 1, math.max(0, W - x + 1)))
end

--- Rotulo a esquerda, valor a direita, na mesma linha.
local function row(y, label, value, fg)
  if y < 1 or y > H then return end
  writeAt(2, y, label, C.dim)
  local v = tostring(value)
  writeAt(math.max(2, W - #v), y, v, fg or C.fg)
end

--- Barra horizontal preenchida por cor de fundo.
local function bar(x, y, w, pct, fill)
  if y < 1 or y > H or w < 1 then return end
  pct = math.max(0, math.min(100, pct or 0))
  local n = math.floor(w * pct / 100 + 0.5)
  paint(C.fg, fill)
  buf.setCursorPos(x, y)
  buf.write(string.rep(" ", n))
  paint(C.fg, C.bar)
  buf.write(string.rep(" ", w - n))
  paint()
end

local function pctColor(p)
  if not color then return C.fg end
  if p == nil then return C.dim end
  if p >= 60 then return C.ok end
  if p >= 25 then return C.warn end
  return C.bad
end

-- ------------------------------------------------------------------ historico

local hist = {}

local function pushHist(v)
  hist[#hist + 1] = v
  while #hist > HIST_MAX do table.remove(hist, 1) end
end

--- Grafico de colunas do historico, ocupando `rows` linhas a partir de y.
local function graph(y, rows)
  if rows < 2 then return end
  local w = W - 2
  local n = math.min(#hist, w)
  writeAt(2, y - 1, "POTENCIA", C.dim)
  if n < 2 then
    writeAt(2, y + math.floor(rows / 2), "coletando dados...", C.dim)
    return
  end

  local peak = 0
  for i = #hist - n + 1, #hist do
    if hist[i] > peak then peak = hist[i] end
  end
  if peak <= 0 then peak = 1 end
  writeAt(2, y - 1, "POTENCIA  pico " .. pgapi.fmt(peak, "W"), C.dim)

  for col = 1, n do
    local v = hist[#hist - n + col]
    local filled = math.floor((v / peak) * rows + 0.5)
    for r = 1, rows do
      local lit = (rows - r + 1) <= filled   -- linha de baixo = r maior
      local yy = y + r - 1
      if yy >= 1 and yy <= H then
        local fill = C.bg
        if lit then fill = color and C.title or C.fg end
        paint(C.fg, fill)
        buf.setCursorPos(1 + col, yy)
        buf.write(" ")
      end
    end
  end
  paint()
end

-- --------------------------------------------------------------------- render

local showGraph = true

local function render()
  buf.setBackgroundColor(C.bg)
  buf.clear()

  -- cabecalho
  paint(C.bg, C.title)
  buf.setCursorPos(1, 1)
  buf.write(string.rep(" ", W))
  writeAt(2, 1, "POWERGRID", C.bg, C.title)
  local clock = pgapi.gameClock() .. (pgapi.isDaytime() and " dia" or " noite")
  writeAt(math.max(2, W - #clock), 1, clock, C.bg, C.title)
  paint()

  local y = 3
  local total, nPower = pgapi.totalPower(scan)
  pushHist(total)

  -- destaque: potencia total
  if nPower > 0 then
    writeAt(2, y, "GERACAO TOTAL", C.dim)
    local s = pgapi.fmt(total, "W")
    writeAt(math.max(2, W - #s), y, s, C.accent)
    y = y + 2
  end

  -- baterias
  if #scan.battery > 0 then
    writeAt(2, y, "BATERIAS", C.title)
    y = y + 1
    for _, e in ipairs(scan.battery) do
      if y > H - 2 then break end
      local b = pgapi.readBattery(e)
      if b then
        local c = pctColor(b.pct)
        local pctTxt = b.pct and string.format("%.0f", b.pct) or "--"
        row(y, e.name, pctTxt .. "%  " .. pgapi.fmt(b.energy, "J", 1), c)
        bar(2, y + 1, W - 2, b.pct, c)
        y = y + 2
        if b.draw and math.abs(b.draw) > 1e-6 then
          local verbo = b.draw >= 0 and "carga " or "descarga "
          writeAt(2, y, verbo .. pgapi.fmt(math.abs(b.draw), "W"), C.dim)
          y = y + 1
        end
      end
    end
    y = y + 1
  end

  -- medidores
  local function gaugeSection(title, list, cat)
    if #list == 0 or y > H - 2 then return end
    writeAt(2, y, title, C.title)
    y = y + 1
    for _, e in ipairs(list) do
      if y > H - 1 then return end
      local g = pgapi.readGauge(e, cat)
      if g then
        local txt = pgapi.fmt(g.value, g.unit)
        if g.pct then txt = txt .. string.format("  %.0f%%", g.pct) end
        row(y, e.name, txt, C.fg)
        y = y + 1
      end
    end
    y = y + 1
  end

  gaugeSection("POTENCIA", scan.power,   "power")
  gaugeSection("TENSAO",   scan.voltage, "voltage")
  gaugeSection("CORRENTE", scan.current, "current")

  -- geradores
  if #scan.clutch > 0 and y <= H - 1 then
    writeAt(2, y, "GERADORES", C.title)
    y = y + 1
    for _, e in ipairs(scan.clutch) do
      if y > H - 1 then break end
      local c = pgapi.readClutch(e)
      if c then
        row(y, e.name, string.format("%.0f RPM  %s", c.rpm, c.mode), C.fg)
        y = y + 1
      end
    end
    y = y + 1
  end

  -- energia acumulada
  if #scan.energy > 0 and y <= H - 1 then
    writeAt(2, y, "ENERGIA ACUMULADA", C.title)
    y = y + 1
    for _, e in ipairs(scan.energy) do
      if y > H - 1 then break end
      local m = pgapi.readEnergyMeter(e)
      if m then
        row(y, e.name, pgapi.fmt(m.energy, "J", 1), C.fg)
        y = y + 1
      end
    end
    y = y + 1
  end

  -- grafico no espaco que sobrar
  if showGraph and nPower > 0 then
    local free = H - y - 1
    if free >= 3 then graph(y + 1, free) end
  end

  -- aviso quando nada foi encontrado
  local nDev = #scan.battery + #scan.power + #scan.voltage + #scan.current
             + #scan.clutch + #scan.energy
  if nDev == 0 then
    writeAt(2, 3, "Nenhum periferico PowerGrid encontrado.", C.bad)
    writeAt(2, 5, "Ligue medidores/baterias ao computador com", C.dim)
    writeAt(2, 6, "Wired Modem + cabo de rede, e tecle R.", C.dim)
  end

  buf.setVisible(true)
  buf.setVisible(false)
end

-- ----------------------------------------------------------------- principal

local function ticker()
  while true do
    render()
    sleep(REFRESH)
  end
end

local function keyLoop()
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q then
      return
    elseif key == keys.r then
      scan = pgapi.scan()
    elseif key == keys.g then
      showGraph = not showGraph
    end
  end
end

local function touchLoop()
  while true do
    os.pullEvent("monitor_touch")
    scan = pgapi.scan()
  end
end

parallel.waitForAny(ticker, keyLoop, touchLoop)

-- restaura as telas ao sair
buf.setVisible(false)
if isMonitor then
  out.setBackgroundColor(colors.black)
  out.clear()
  out.setCursorPos(1, 1)
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("pgmon encerrado.")
