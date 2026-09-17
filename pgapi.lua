--[[ pgapi - biblioteca de acesso aos perifericos do PowerGrid (CC:Tweaked)
     Usada por pgmon e suntrack.

     Tipos de periferico expostos pelo PowerGrid 0.6.1:
       powergrid_battery            capacity() energy() chargePercentage() powerDraw()
       powergrid_voltage_gauge      voltage()  getValue() maxRange() rangePercentage()
       powergrid_current_gauge      current()  getValue() maxRange() rangePercentage()
       powergrid_power_gauge        power()    getValue() maxRange() rangePercentage()
       powergrid_energy_meter       energy()   getValue() maxRange()
       powergrid_generator_clutch   mode() load() rpm()
       powergrid_redstone_converter setValue(n) clearValue()

     ATENCAO: chargePercentage() e rangePercentage() devolvem FRACAO (0..1),
     nao 0..100 - apesar do nome. pgapi ja normaliza para 0..100 em .pct.
]]

local pgapi = {}

pgapi.TYPE = {
  battery  = "powergrid_battery",
  voltage  = "powergrid_voltage_gauge",
  current  = "powergrid_current_gauge",
  power    = "powergrid_power_gauge",
  energy   = "powergrid_energy_meter",
  clutch   = "powergrid_generator_clutch",
  redstone = "powergrid_redstone_converter",
  -- Redstone Relay do proprio CC:Tweaked: um bloco com Wired Modem que leva
  -- redstone pela rede de cabo. E o que permite colar embreagem e cambio
  -- longe do computador, na mesma rede do medidor - sem ele, redstone so
  -- funciona encostado ou por fio de redstone comum.
  relay    = "redstone_relay",
}

-- tipos que sao medidores de geracao, na ordem de preferencia (potencia e
-- corrente acompanham a irradiancia; tensao quase nao muda com a luz)
pgapi.MEDIDORES = { "power", "current", "voltage" }

-- PowerGrid renomeou os medidores numa atualizacao (Gauge -> ammeter /
-- voltmeter / powermeter), sem mudar a versao no mods.toml. O tipo do
-- periferico muda, mas a API Lua (voltage()/current()/power(), getValue(),
-- maxRange(), rangePercentage()) parece a mesma. Aceita os dois nomes na
-- mesma categoria, para funcionar com blocos antigos e novos juntos.
pgapi.APELIDOS = {
  ammeter    = "current",
  voltmeter  = "voltage",
  powermeter = "power",
}

-- categoria por tipo, para a varredura
local CAT = {}
for cat, t in pairs(pgapi.TYPE) do CAT[t] = cat end
for t, cat in pairs(pgapi.APELIDOS) do CAT[t] = cat end

--- Chamada tolerante a falha: o bloco pode ter sido quebrado entre ticks.
-- @return valor ou nil
function pgapi.try(dev, method, ...)
  if type(dev) ~= "table" or type(dev[method]) ~= "function" then return nil end
  local ok, v = pcall(dev[method], ...)
  if ok then return v end
  return nil
end

--- Varre todos os perifericos conectados e agrupa por categoria.
-- @return tabela { battery = { {name=,dev=}, ... }, voltage = {...}, ..., monitor = {...} }
function pgapi.scan()
  local out = { monitor = {} }
  for cat in pairs(pgapi.TYPE) do out[cat] = {} end

  for _, name in ipairs(peripheral.getNames()) do
    local dev = peripheral.wrap(name)
    if dev then
      if peripheral.hasType(name, "monitor") then
        table.insert(out.monitor, { name = name, dev = dev })
      end
      for t, cat in pairs(CAT) do
        if peripheral.hasType(name, t) then
          table.insert(out[cat], { name = name, dev = dev })
        end
      end
    end
  end

  -- ordem estavel entre reinicios: o CC nao garante ordem em getNames()
  for _, list in pairs(out) do
    table.sort(list, function(a, b) return a.name < b.name end)
  end
  return out
end

--- Le um medidor (voltage/current/power) de forma uniforme.
-- @return { value=, max=, pct=, unit= } ou nil
function pgapi.readGauge(entry, cat)
  local d = entry.dev
  local getter = ({ voltage = "voltage", current = "current", power = "power" })[cat]
  local value = pgapi.try(d, getter)
  if value == nil then value = pgapi.try(d, "getValue") end
  if value == nil then return nil end

  local max  = pgapi.try(d, "maxRange")
  local frac = pgapi.try(d, "rangePercentage")
  return {
    value = value,
    max   = max,
    pct   = frac and (frac * 100) or nil,
    unit  = ({ voltage = "V", current = "A", power = "W" })[cat] or "",
  }
end

--- Le uma bateria.
-- @return { energy=, capacity=, pct=, draw= } ou nil
function pgapi.readBattery(entry)
  local d = entry.dev
  local e = pgapi.try(d, "energy")
  if e == nil then return nil end
  local cap  = pgapi.try(d, "capacity")
  local frac = pgapi.try(d, "chargePercentage")
  if frac == nil and cap and cap > 0 then frac = e / cap end
  return {
    energy   = e,
    capacity = cap,
    pct      = frac and (frac * 100) or nil,
    draw     = pgapi.try(d, "powerDraw"),
  }
end

--- Le uma embreagem de gerador.
function pgapi.readClutch(entry)
  local d = entry.dev
  local rpm = pgapi.try(d, "rpm")
  if rpm == nil then return nil end
  return { rpm = rpm, load = pgapi.try(d, "load"), mode = pgapi.try(d, "mode") or "?" }
end

--- Le um medidor de energia acumulada.
function pgapi.readEnergyMeter(entry)
  local d = entry.dev
  local e = pgapi.try(d, "energy")
  if e == nil then e = pgapi.try(d, "getValue") end
  if e == nil then return nil end
  return { energy = e, max = pgapi.try(d, "maxRange") }
end

local UNIDADE = { power = "W", current = "A", voltage = "V" }

--- Escolhe qual grupo de medidor usar para acompanhar a geracao.
-- nome == "auto" ou nil: prefere potencia, depois corrente, depois tensao.
-- nome == algo especifico: usa so o periferico com esse nome, em qualquer
-- categoria de medidor - devolve lista de 1 item.
-- @return lista, categoria ("power"/"current"/"voltage"), unidade
function pgapi.escolherMedidor(scan, nome)
  if nome and nome ~= "" and nome ~= "auto" then
    for _, cat in ipairs(pgapi.MEDIDORES) do
      for _, e in ipairs(scan[cat]) do
        if e.name == nome then return { e }, cat, UNIDADE[cat] end
      end
    end
    return {}, nil, ""
  end

  for _, cat in ipairs(pgapi.MEDIDORES) do
    if #scan[cat] > 0 then return scan[cat], cat, UNIDADE[cat] end
  end
  return {}, nil, ""
end

--- Acha um periferico monitor pelo nome, ou o primeiro disponivel.
-- nome == "auto"/"nenhum"/nil: primeiro monitor achado (ou nenhum, para "nenhum").
function pgapi.escolherMonitor(scan, nome)
  if nome == "nenhum" then return nil end
  if nome and nome ~= "" and nome ~= "auto" then
    for _, e in ipairs(scan.monitor) do
      if e.name == nome then return e end
    end
    return nil
  end
  return scan.monitor[1]
end

--- Soma a potencia gerada/consumida vista por todos os medidores de potencia.
function pgapi.totalPower(scan)
  local sum, n = 0, 0
  for _, e in ipairs(scan.power) do
    local r = pgapi.readGauge(e, "power")
    if r then sum = sum + r.value; n = n + 1 end
  end
  return sum, n
end

-- ---------------------------------------------------------------- formatacao

local PREFIX = { { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" }, { 1, "" }, { 1e-3, "m" } }

--- Formata um numero com prefixo SI. fmt(1523, "W") -> "1.52 kW"
function pgapi.fmt(v, unit, casas)
  if v == nil then return "--" end
  unit = unit or ""
  casas = casas or 2
  local a = math.abs(v)
  if a < 1e-9 then return string.format("0 %s", unit) end
  for _, p in ipairs(PREFIX) do
    if a >= p[1] then
      return string.format("%." .. casas .. "f %s%s", v / p[1], p[2], unit)
    end
  end
  return string.format("%.2e %s", v, unit)
end

--- Hora do jogo como "HH:MM" (os.time() no CC devolve 0..24 em horas).
function pgapi.gameClock()
  local t = os.time()
  local h = math.floor(t)
  local m = math.floor((t - h) * 60)
  return string.format("%02d:%02d", h % 24, m)
end

--- true entre o nascer e o por do sol (aprox.), pelo relogio do jogo.
function pgapi.isDaytime()
  local t = os.time()
  return t >= 5.5 and t <= 18.5
end

return pgapi
