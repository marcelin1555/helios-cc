--[[ install - instalador do sistema HELIOS ]]

local ARQUIVOS = {}
local ORDEM = { "pgapi.lua", "ui.lua", "config.lua", "pixel.lua", "palette.lua", "rendimento.lua", "clima.lua", "circuito.lua", "boot.lua", "pgmon.lua", "suntrack.lua", "painel.lua", "configurar.lua", "soldemo.lua", "startup.lua" }
ARQUIVOS["pgapi.lua"] = [=[
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

-- categoria por tipo, para a varredura
local CAT = {}
for cat, t in pairs(pgapi.TYPE) do CAT[t] = cat end

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

return pgapi]=]
ARQUIVOS["ui.lua"] = [=[
--[[ ui - biblioteca de interface para os programas do sistema

     Desenha com cores de fundo em vez de caracteres de moldura: funciona
     em qualquer fonte e em qualquer tamanho de tela, do terminal 51x19 do
     Advanced Computer ate um monitor grande.

     local ui = dofile("ui.lua")
     local tela = ui.tela(term.current())
     tela:limpar()
     tela:cabecalho("HELIOS", "12:30")
     tela:centro(8, "ola", ui.C.destaque)
     tela:mostrar()
]]

local ui = {}

-- paleta unica do sistema
ui.C = {
  fundo     = colors.black,
  texto     = colors.white,
  fraco     = colors.gray,
  destaque  = colors.cyan,
  bom       = colors.lime,
  atencao   = colors.orange,
  ruim      = colors.red,
  acento    = colors.yellow,
  trilho    = colors.gray,
}

-- paleta alternativa para telas sem cor
local MONO = {
  fundo = colors.black, texto = colors.white, fraco = colors.white,
  destaque = colors.white, bom = colors.white, atencao = colors.white,
  ruim = colors.white, acento = colors.white, trilho = colors.black,
}

local Tela = {}
Tela.__index = Tela

--- Cria uma tela sobre um terminal ou monitor.
-- Desenha num buffer fora de tela: nada pisca enquanto e montado.
function ui.tela(destino, semBuffer)
  local self = setmetatable({}, Tela)
  self.destino = destino
  self.w, self.h = destino.getSize()
  self.cor = (destino.isColour and destino.isColour()) and true or false
  self.C = self.cor and ui.C or MONO
  if semBuffer then
    self.buf = destino
    self.direto = true
  else
    self.buf = window.create(destino, 1, 1, self.w, self.h, false)
    self.direto = false
  end
  return self
end

function Tela:pintar(fg, bg)
  self.buf.setTextColor(fg or self.C.texto)
  self.buf.setBackgroundColor(bg or self.C.fundo)
end

function Tela:limpar(bg)
  self.buf.setBackgroundColor(bg or self.C.fundo)
  self.buf.setTextColor(self.C.texto)
  self.buf.clear()
end

--- Escreve texto cortando no limite da tela.
function Tela:texto(x, y, s, fg, bg)
  if y < 1 or y > self.h then return end
  s = tostring(s)
  if x < 1 then s = s:sub(2 - x); x = 1 end
  if x > self.w then return end
  self:pintar(fg, bg)
  self.buf.setCursorPos(x, y)
  self.buf.write(s:sub(1, self.w - x + 1))
end

function Tela:centro(y, s, fg, bg)
  s = tostring(s)
  self:texto(math.floor((self.w - #s) / 2) + 1, y, s, fg, bg)
end

function Tela:direita(y, s, fg, bg)
  s = tostring(s)
  self:texto(self.w - #s, y, s, fg, bg)
end

--- Linha preenchida de ponta a ponta, para faixas e separadores.
function Tela:faixa(y, bg)
  if y < 1 or y > self.h then return end
  self:pintar(self.C.texto, bg or self.C.destaque)
  self.buf.setCursorPos(1, y)
  self.buf.write((" "):rep(self.w))
end

--- Retangulo solido.
function Tela:caixa(x, y, w, h, bg)
  for i = 0, h - 1 do
    if y + i >= 1 and y + i <= self.h then
      self:pintar(self.C.texto, bg)
      self.buf.setCursorPos(x, y + i)
      self.buf.write((" "):rep(math.max(0, math.min(w, self.w - x + 1))))
    end
  end
end

--- Barra de progresso. pct de 0 a 100.
function Tela:barra(x, y, w, pct, cor, corTrilho)
  if y < 1 or y > self.h or w < 1 then return end
  pct = math.max(0, math.min(100, pct or 0))
  local n = math.floor(w * pct / 100 + 0.5)
  self:pintar(self.C.texto, cor or self.C.destaque)
  self.buf.setCursorPos(x, y)
  self.buf.write((" "):rep(n))
  self:pintar(self.C.texto, corTrilho or self.C.trilho)
  self.buf.write((" "):rep(w - n))
  self:pintar()
end

--- Rotulo a esquerda e valor a direita, na mesma linha.
function Tela:linha(y, rotulo, valor, corValor, corRotulo)
  self:texto(2, y, rotulo, corRotulo or self.C.fraco)
  local v = tostring(valor)
  self:texto(self.w - #v, y, v, corValor or self.C.texto)
end

--- Faixa de titulo no topo, com um canto a direita opcional.
function Tela:cabecalho(titulo, canto)
  self:faixa(1, self.C.destaque)
  self:texto(2, 1, titulo, self.C.fundo, self.C.destaque)
  if canto then
    self:texto(self.w - #canto, 1, canto, self.C.fundo, self.C.destaque)
  end
end

--- Rodape com dica de teclas.
function Tela:rodape(dica)
  self:faixa(self.h, self.C.trilho)
  self:texto(2, self.h, dica, self.C.texto, self.C.trilho)
end

--- Marcador de estado: [ ok ] / [ -- ] / [ !! ]
-- estado: "bom", "fraco", "ruim", "atencao"
function Tela:estado(x, y, estado, rotulo)
  local marca = ({ bom = " ok ", fraco = " -- ", ruim = " !! ", atencao = " ~~ " })[estado] or " ?? "
  local cor   = ({ bom = self.C.bom, fraco = self.C.fraco,
                   ruim = self.C.ruim, atencao = self.C.atencao })[estado] or self.C.fraco
  self:texto(x, y, marca, self.C.fundo, cor)
  if rotulo then
    self:texto(x + 5, y, rotulo, estado == "fraco" and self.C.fraco or self.C.texto)
  end
end

--- Joga o buffer na tela de uma vez so.
function Tela:mostrar()
  if self.direto then return end
  self.buf.setVisible(true)
  self.buf.setVisible(false)
end

--- Devolve a tela ao estado normal ao sair de um programa.
function Tela:encerrar()
  if not self.direto then self.buf.setVisible(false) end
  self.destino.setBackgroundColor(colors.black)
  self.destino.setTextColor(colors.white)
  self.destino.clear()
  self.destino.setCursorPos(1, 1)
end

-- ------------------------------------------------------------------ efeitos

--- Escreve caractere a caractere. Use com parcimonia - so no boot.
function Tela:digitar(x, y, s, fg, atraso)
  atraso = atraso or 0.02
  for i = 1, #s do
    self:texto(x, y, s:sub(1, i), fg)
    self:mostrar()
    sleep(atraso)
  end
end

--- Menu navegavel. itens = { {rotulo=, dica=}, ... }
-- Devolve o indice escolhido, ou nil se o usuario apertou Q.
function Tela:menu(y0, itens, titulo)
  local sel = 1
  while true do
    if titulo then self:texto(2, y0 - 2, titulo, self.C.fraco) end
    for i, item in ipairs(itens) do
      local y = y0 + (i - 1) * 2
      local ativo = (i == sel)
      local bg = ativo and self.C.destaque or self.C.fundo
      local fg = ativo and self.C.fundo or self.C.texto
      self:caixa(1, y, self.w, 1, bg)
      self:texto(3, y, item.rotulo, fg, bg)
      if item.dica then
        self:texto(self.w - #item.dica - 1, y, item.dica,
                   ativo and self.C.fundo or self.C.fraco, bg)
      end
    end
    self:mostrar()

    local _, tecla = os.pullEvent("key")
    if tecla == keys.up then
      sel = sel > 1 and sel - 1 or #itens
    elseif tecla == keys.down then
      sel = sel < #itens and sel + 1 or 1
    elseif tecla == keys.enter then
      return sel
    elseif tecla == keys.q then
      return nil
    elseif tecla >= keys.one and tecla <= keys.nine then
      local n = tecla - keys.one + 1
      if itens[n] then return n end
    end
  end
end

return ui]=]
ARQUIVOS["config.lua"] = [=[
--[[ config - o lugar unico de configuracao do HELIOS

  Tudo que depende da SUA montagem mora em /helios.cfg: qual medidor ler, em que
  rele e lado estao a embreagem e o cambio, qual monitor usar, quantos paineis
  existem e os ajustes finos do rastreio.

  O arquivo e Lua comentado. Da para editar na mao com `edit helios.cfg`, mas o
  jeito facil e rodar `configurar`, que lista o que existe na rede.

    local config = require("config")
    local cfg = config.ler()      -- nunca falha: sem arquivo, usa o padrao
    config.salvar(cfg)

  Quem ja tinha suntrack.cfg / painel.cfg (versao antiga) nao perde a montagem:
  sem helios.cfg, eles sao lidos e convertidos.
]]

local config = {}

config.ARQUIVO = "/helios.cfg"

config.LADOS = { "top", "bottom", "left", "right", "front", "back" }

--- "computador" usa o redstone do proprio computador; qualquer outro valor e o
-- nome de um redstone_relay na rede de cabo.
config.COMPUTADOR = "computador"
config.NENHUM = "nenhum"
config.AUTO = "auto"

local function padrao()
  return {
    medidor = config.AUTO,
    monitor = config.AUTO,
    embreagem = {
      rele = config.COMPUTADOR,
      lado = "back",
      invertida = false,
      analogica = false,
      nivelGiro = 0,
    },
    cambio = {
      rele = config.NENHUM,
      lado = "top",
    },
    paineis = 0,
    rastreio = {
      pulso = 0.30,
      assentar = 0.60,
      amostras = 3,
      intervaloAmostra = 0.15,
      conferir = 8,
      bandaMorta = 0.02,
      rearmar = 0.35,
      confirmacoes = 3,
      espera = 90,
      volta = 24,
      potenciaNoite = 0.5,
      checagemNoite = 20,
      bateriaCheia = 95,
      bateriaRetoma = 88,
    },
  }
end
config.padrao = padrao

--- Copia por cima do padrao so o que tem o mesmo tipo. Chave desconhecida ou
-- valor de tipo errado e ignorado: um erro de digitacao no arquivo nao pode
-- derrubar o rastreador, so voltar aquele item ao padrao.
local function mesclar(base, novo)
  if type(novo) ~= "table" then return base end
  for k, v in pairs(base) do
    local n = novo[k]
    if type(v) == "table" then
      mesclar(v, n)
    elseif n ~= nil and type(n) == type(v) then
      base[k] = n
    end
  end
  return base
end

-- ------------------------------------------------------------------ leitura

local function lerArquivo(caminho)
  if not fs.exists(caminho) then return nil end
  local f = fs.open(caminho, "r")
  if not f then return nil end
  local texto = f.readAll()
  f.close()
  -- ambiente vazio: o arquivo so pode devolver uma tabela, nao chamar nada
  local fn = load(texto, "=" .. caminho, "t", {})
  if not fn then return nil, "helios.cfg com erro de sintaxe" end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" then return nil, "helios.cfg nao devolve uma tabela" end
  return t
end

--- Le suntrack.cfg / painel.cfg da versao antiga (chave=valor).
local function lerLegado()
  local function pares(caminho)
    if not fs.exists(caminho) then return nil end
    local f = fs.open(caminho, "r")
    if not f then return nil end
    local t = {}
    while true do
      local linha = f.readLine()
      if not linha then break end
      local k, v = linha:match("^%s*([%w_]+)%s*=%s*([%w%.%-_]+)%s*$")
      if k then t[k] = tonumber(v) or v end
    end
    f.close()
    return t
  end

  local s = pares("/suntrack.cfg")
  local p = pares("/painel.cfg")
  if not s and not p then return nil end

  local cfg = padrao()
  s = s or {}
  if s.clutchSide then cfg.embreagem.lado = s.clutchSide end
  if s.gearSide and s.gearSide ~= "" then
    cfg.cambio.rele = config.COMPUTADOR
    cfg.cambio.lado = s.gearSide
  end
  cfg.embreagem.invertida = (s.invertClutch == 1)
  cfg.embreagem.analogica = (s.clutchAnalog == 1)
  if type(s.runLevel) == "number" then cfg.embreagem.nivelGiro = s.runLevel end

  local mapa = {
    pulse = "pulso", settle = "assentar", samples = "amostras",
    sampleGap = "intervaloAmostra", holdCheck = "conferir",
    deadband = "bandaMorta", reacquire = "rearmar", confirma = "confirmacoes",
    cooldown = "espera", sweepTime = "volta", nightPower = "potenciaNoite",
    nightCheck = "checagemNoite", battFull = "bateriaCheia",
    battResume = "bateriaRetoma",
  }
  for velho, novo in pairs(mapa) do
    if type(s[velho]) == "number" then cfg.rastreio[novo] = s[velho] end
  end

  if p and type(p.paineis) == "number" then cfg.paineis = p.paineis end
  return cfg
end

--- Le a configuracao. Nunca falha.
-- @return cfg, origem ("arquivo" | "legado" | "padrao"), aviso ou nil
function config.ler()
  local t, erro = lerArquivo(config.ARQUIVO)
  if t then return mesclar(padrao(), t), "arquivo" end

  local legado = lerLegado()
  if legado then
    -- migra de uma vez: helios.cfg passa a ser a fonte da verdade, e o
    -- resultado nao fica preso a suntrack.cfg/painel.cfg sobrevivendo por ai
    config.salvar(legado)
    return legado, "legado", erro
  end

  return padrao(), "padrao", erro
end

-- ------------------------------------------------------------------ escrita

local function q(s) return string.format("%q", tostring(s)) end
local function b(v) return v and "true" or "false" end
local function n(v) return tostring(v) end

--- Grava o arquivo comentado, na ordem em que faz sentido ler.
function config.salvar(cfg)
  local e, c, r = cfg.embreagem, cfg.cambio, cfg.rastreio
  local linhas = {
    "-- HELIOS - configuracao da montagem",
    "-- Gerado por 'configurar'. Pode editar na mao; valor invalido volta ao padrao.",
    "return {",
    "  -- medidor na saida do bearing: nome do periferico ou \"auto\"",
    "  medidor = " .. q(cfg.medidor) .. ",",
    "",
    "  -- monitor do painel: nome, \"auto\" ou \"nenhum\"",
    "  monitor = " .. q(cfg.monitor) .. ",",
    "",
    "  -- embreagem (Clutch do Create): redstone trava o painel",
    "  embreagem = {",
    "    rele = " .. q(e.rele) .. ",   -- redstone_relay_N, ou \"computador\"",
    "    lado = " .. q(e.lado) .. ",",
    "    invertida = " .. b(e.invertida) .. ",   -- true se ha tocha invertendo",
    "    analogica = " .. b(e.analogica) .. ",   -- true para Generator Clutch",
    "    nivelGiro = " .. n(e.nivelGiro) .. ",   -- so analogica: 0 = torque total",
    "  },",
    "",
    "  -- cambio (Gearshift): redstone inverte o sentido",
    "  cambio = {",
    "    rele = " .. q(c.rele) .. ",   -- redstone_relay_N, \"computador\" ou \"nenhum\"",
    "    lado = " .. q(c.lado) .. ",",
    "  },",
    "",
    "  -- quantos paineis no bearing; 0 = nao compara com o catalogo",
    "  paineis = " .. n(cfg.paineis) .. ",",
    "",
    "  -- ajuste fino do rastreio (segundos, fracoes de 0 a 1, ou %)",
    "  rastreio = {",
    "    pulso = " .. n(r.pulso) .. ",",
    "    assentar = " .. n(r.assentar) .. ",",
    "    amostras = " .. n(r.amostras) .. ",",
    "    intervaloAmostra = " .. n(r.intervaloAmostra) .. ",",
    "    conferir = " .. n(r.conferir) .. ",",
    "    bandaMorta = " .. n(r.bandaMorta) .. ",",
    "    rearmar = " .. n(r.rearmar) .. ",",
    "    confirmacoes = " .. n(r.confirmacoes) .. ",",
    "    espera = " .. n(r.espera) .. ",",
    "    volta = " .. n(r.volta) .. ",   -- segundos de uma volta completa",
    "    potenciaNoite = " .. n(r.potenciaNoite) .. ",",
    "    checagemNoite = " .. n(r.checagemNoite) .. ",",
    "    bateriaCheia = " .. n(r.bateriaCheia) .. ",",
    "    bateriaRetoma = " .. n(r.bateriaRetoma) .. ",",
    "  },",
    "}",
    "",
  }
  local f = fs.open(config.ARQUIVO, "w")
  if not f then return false end
  f.write(table.concat(linhas, "\n"))
  f.close()
  return true
end

--- Descricao curta de uma saida, para telas: "redstone_relay_0 top".
function config.descrever(saida)
  if not saida or saida.rele == config.NENHUM then return "nenhum" end
  return saida.rele .. " " .. saida.lado
end

-- --------------------------------------------------------------- redstone

--- O alvo real de uma saida: a API nativa "redstone", ou o periferico
-- Redstone Relay colado na rede de cabo. E o relay que permite a embreagem
-- e o cambio ficarem longe do computador, na mesma rede do medidor.
local function alvo(saida)
  if not saida or saida.rele == config.NENHUM then return nil end
  if saida.rele == config.COMPUTADOR then return redstone end
  return peripheral.wrap(saida.rele)
end

--- Liga/desliga um sinal booleano num lado (usado pelo cambio).
function config.setBool(saida, ligado)
  local t = alvo(saida)
  if not t then return false end
  return pcall(t.setOutput, saida.lado, ligado == true)
end

--- Sinal de 0 a 15 (usado pela embreagem, que pode ser analogica).
-- invertida troca o sentido do sinal, para quem tem uma tocha no caminho.
function config.setNivel(saida, nivel)
  local t = alvo(saida)
  if not t then return false end
  nivel = math.max(0, math.min(15, tonumber(nivel) or 0))
  if saida.invertida then nivel = 15 - nivel end
  if saida.analogica then
    return pcall(t.setAnalogOutput, saida.lado, nivel)
  end
  return pcall(t.setOutput, saida.lado, nivel > 0)
end

--- A saida esta configurada e o alvo existe na rede agora?
function config.saidaOk(saida)
  if not saida or saida.rele == config.NENHUM then return true end -- opcional
  return alvo(saida) ~= nil
end

return config]=]
ARQUIVOS["pixel.lua"] = [=[
--[[ pixel - framebuffer subpixel 2x3 para CC:Tweaked

  Cada celula do terminal cobre 6 pontos:

      bit0  bit1        1   2
      bit2  bit3   =    4   8
      bit4  bit5       16  32

  Os caracteres 128..159 desenham os CINCO primeiros pontos sobre um par de
  cores; o ponto de baixo a direita fica sempre no fundo. Para acender esse
  sexto ponto invertemos: trocamos frente e fundo e complementamos o padrao.

    b5 = 0 -> char 128 + p,        frente = A, fundo = B
    b5 = 1 -> char 128 + (31 - p), frente = B, fundo = A

  Cada linha de celulas vira um unico blit. Num monitor 6x4 sao ~40 chamadas
  por quadro em vez de ~4800.

  Uso:
    local pixel = dofile("pixel.lua")
    local fb = pixel.novo(term.current())
    fb:limpar(colors.black)
    fb:circulo(20, 20, 8, colors.orange, true)
    fb:enviar()
]]

local pixel = {}

-- RGB padrao do CC, usado quando nao da para ler a paleta da tela.
-- Serve para medir distancia entre cores ao resolver celulas com 3+ cores.
local RGB_PADRAO = {
  [colors.white]     = { 0.94, 0.94, 0.94 },
  [colors.orange]    = { 0.95, 0.70, 0.20 },
  [colors.magenta]   = { 0.90, 0.50, 0.73 },
  [colors.lightBlue] = { 0.60, 0.70, 0.90 },
  [colors.yellow]    = { 0.87, 0.87, 0.42 },
  [colors.lime]      = { 0.50, 0.80, 0.10 },
  [colors.pink]      = { 0.95, 0.70, 0.80 },
  [colors.gray]      = { 0.30, 0.30, 0.30 },
  [colors.lightGray] = { 0.60, 0.60, 0.60 },
  [colors.cyan]      = { 0.30, 0.60, 0.70 },
  [colors.purple]    = { 0.70, 0.40, 0.90 },
  [colors.blue]      = { 0.20, 0.35, 0.80 },
  [colors.brown]     = { 0.50, 0.40, 0.24 },
  [colors.green]     = { 0.35, 0.65, 0.30 },
  [colors.red]       = { 0.80, 0.30, 0.30 },
  [colors.black]     = { 0.07, 0.07, 0.07 },
}

--- Digito hexadecimal que o blit usa para cada cor.
local function digito(cor)
  if colors.toBlit then
    local ok, d = pcall(colors.toBlit, cor)
    if ok and d then return d end
  end
  local n = 0
  local v = cor
  while v > 1 do v = v / 2; n = n + 1 end
  return string.sub("0123456789abcdef", n + 1, n + 1)
end

local Frame = {}
Frame.__index = Frame

--- Cria um framebuffer sobre um terminal ou monitor.
function pixel.novo(destino)
  local cw, ch = destino.getSize()
  local self = setmetatable({}, Frame)
  self.destino = destino
  self.cw, self.ch = cw, ch
  self.w, self.h = cw * 2, ch * 3
  self.rgb = {}

  -- a paleta real da tela, quando der para ler; se alguem mexeu nela, a
  -- distancia entre cores muda junto
  for cor, padrao in pairs(RGB_PADRAO) do
    self.rgb[cor] = padrao
    if destino.getPaletteColour then
      local ok, r, g, b = pcall(destino.getPaletteColour, cor)
      if ok and type(r) == "number" then self.rgb[cor] = { r, g, b } end
    end
  end

  self.buf = {}
  self:limpar(colors.black)
  return self
end

function Frame:limpar(cor)
  cor = cor or colors.black
  for y = 1, self.h do
    local linha = {}
    for x = 1, self.w do linha[x] = cor end
    self.buf[y] = linha
  end
end

function Frame:ponto(x, y, cor)
  x, y = math.floor(x), math.floor(y)
  if x < 1 or x > self.w or y < 1 or y > self.h then return end
  self.buf[y][x] = cor
end

--- Bresenham.
function Frame:linha(x1, y1, x2, y2, cor)
  x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
  local dx = math.abs(x2 - x1)
  local dy = -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    self:ponto(x1, y1, cor)
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x1 = x1 + sx end
    if e2 <= dx then err = err + dx; y1 = y1 + sy end
  end
end

function Frame:retangulo(x, y, w, h, cor, preenchido)
  if preenchido then
    for i = y, y + h - 1 do
      for j = x, x + w - 1 do self:ponto(j, i, cor) end
    end
  else
    self:linha(x, y, x + w - 1, y, cor)
    self:linha(x, y + h - 1, x + w - 1, y + h - 1, cor)
    self:linha(x, y, x, y + h - 1, cor)
    self:linha(x + w - 1, y, x + w - 1, y + h - 1, cor)
  end
end

--- Circulo pelo ponto medio.
function Frame:circulo(cx, cy, r, cor, preenchido)
  cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
  if r < 1 then self:ponto(cx, cy, cor); return end
  local x, y = r, 0
  local err = 1 - r
  local function par(px, py)
    if preenchido then
      self:linha(cx - px, py, cx + px, py, cor)
    else
      self:ponto(cx - px, py, cor)
      self:ponto(cx + px, py, cor)
    end
  end
  while x >= y do
    par(x, cy + y); par(x, cy - y)
    par(y, cy + x); par(y, cy - x)
    y = y + 1
    if err < 0 then
      err = err + 2 * y + 1
    else
      x = x - 1
      err = err + 2 * (y - x) + 1
    end
  end
end

-- ---------------------------------------------------------------- conversao

local function dist(a, b)
  local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return dr * dr + dg * dg + db * db
end

--- Resolve 6 pontos numa celula: devolve caractere, cor de frente e de fundo.
-- Exposta para os testes.
function Frame:celula(p)
  -- conta quantas vezes cada cor aparece
  local cont, ordem = {}, {}
  for i = 1, 6 do
    local c = p[i]
    if not cont[c] then cont[c] = 0; ordem[#ordem + 1] = c end
    cont[c] = cont[c] + 1
  end

  -- uma cor so: celula chapada
  if #ordem == 1 then
    return " ", ordem[1], ordem[1]
  end

  -- as duas mais frequentes vencem; empate desempata pela ordem de aparicao,
  -- que e estavel, para o mesmo desenho nao piscar entre quadros
  table.sort(ordem, function(a, b)
    if cont[a] ~= cont[b] then return cont[a] > cont[b] end
    return a < b
  end)
  local A, B = ordem[1], ordem[2]

  -- cores sobrantes vao para a vencedora mais proxima em RGB
  local mapa = {}
  for i = 3, #ordem do
    local c = ordem[i]
    local ra = self.rgb[c] and self.rgb[A] and dist(self.rgb[c], self.rgb[A]) or 0
    local rb = self.rgb[c] and self.rgb[B] and dist(self.rgb[c], self.rgb[B]) or 1
    mapa[c] = (ra <= rb) and A or B
  end
  local function resolve(c)
    if c == A or c == B then return c end
    return mapa[c] or A
  end

  -- bitmask dos pontos que sao da cor A
  local bits = 0
  for i = 1, 6 do
    if resolve(p[i]) == A then bits = bits + 2 ^ (i - 1) end
  end
  bits = math.floor(bits)

  local frente, fundo = A, B
  local baixo = bits >= 32
  if baixo then bits = bits - 32 end
  if baixo then
    -- o sexto ponto nao tem caractere proprio: inverte tudo
    bits = 31 - bits
    frente, fundo = B, A
  end

  return string.char(128 + bits), frente, fundo
end

--- Converte o buffer inteiro e joga na tela, um blit por linha.
function Frame:enviar()
  local d = self.destino
  local p = {}
  for cy = 1, self.ch do
    local texto, fg, bg = {}, {}, {}
    local y0 = (cy - 1) * 3
    local l1, l2, l3 = self.buf[y0 + 1], self.buf[y0 + 2], self.buf[y0 + 3]
    for cx = 1, self.cw do
      local x0 = (cx - 1) * 2
      p[1], p[2] = l1[x0 + 1], l1[x0 + 2]
      p[3], p[4] = l2[x0 + 1], l2[x0 + 2]
      p[5], p[6] = l3[x0 + 1], l3[x0 + 2]
      local ch, frente, fundo = self:celula(p)
      texto[cx] = ch
      fg[cx] = digito(frente)
      bg[cx] = digito(fundo)
    end
    d.setCursorPos(1, cy)
    d.blit(table.concat(texto), table.concat(fg), table.concat(bg))
  end
end

return pixel]=]
ARQUIVOS["palette.lua"] = [=[
--[[ palette - paletas nomeadas e transicao suave entre elas

  As 16 cores do CC sao redefiniveis com term.setPaletteColour, e a mudanca
  vale para a TELA INTEIRA. E o que permite fazer o amanhecer sem redesenhar
  nada: o sol e desenhado uma vez e so as cores mudam.

  CUIDADO: a paleta e global e persiste depois que o programa termina. Se
  ninguem restaurar, o shell, o edit e todo o resto ficam com as cores erradas
  ate o computador reiniciar. Por isso:

    local antes = palette.guardar(tela)
    ... mexe a vontade ...
    palette.restaurar(tela, antes)      -- em pcall, em TODO caminho de saida

  Use palette.com(tela, funcao) quando puder: ele faz isso sozinho.
]]

local palette = {}

--- Cores que as paletas deste sistema mexem. As outras ficam como estao,
-- para nao estragar a aparencia de outros programas que rodem depois.
local MEXIDAS = {
  colors.white, colors.orange, colors.yellow, colors.red,
  colors.gray, colors.lightGray, colors.cyan, colors.blue,
  colors.lime, colors.black,
}

palette.MEXIDAS = MEXIDAS

--- Paletas do amanhecer. Valores RGB de 0 a 1.
palette.PALETAS = {
  noite = {
    [colors.white]     = { 0.55, 0.58, 0.72 },
    [colors.orange]    = { 0.24, 0.22, 0.36 },
    [colors.yellow]    = { 0.32, 0.32, 0.48 },
    [colors.red]       = { 0.20, 0.16, 0.30 },
    [colors.gray]      = { 0.14, 0.15, 0.24 },
    [colors.lightGray] = { 0.30, 0.32, 0.45 },
    [colors.cyan]      = { 0.20, 0.28, 0.45 },
    [colors.blue]      = { 0.10, 0.13, 0.28 },
    [colors.lime]      = { 0.25, 0.35, 0.40 },
    [colors.black]     = { 0.02, 0.02, 0.06 },
  },
  amanhecer = {
    [colors.white]     = { 0.92, 0.86, 0.78 },
    [colors.orange]    = { 0.86, 0.45, 0.18 },
    [colors.yellow]    = { 0.92, 0.68, 0.28 },
    [colors.red]       = { 0.70, 0.26, 0.20 },
    [colors.gray]      = { 0.32, 0.24, 0.24 },
    [colors.lightGray] = { 0.58, 0.50, 0.46 },
    [colors.cyan]      = { 0.45, 0.48, 0.55 },
    [colors.blue]      = { 0.22, 0.22, 0.38 },
    [colors.lime]      = { 0.45, 0.60, 0.30 },
    [colors.black]     = { 0.06, 0.04, 0.07 },
  },
  dia = {
    [colors.white]     = { 0.94, 0.94, 0.94 },
    [colors.orange]    = { 0.95, 0.70, 0.20 },
    [colors.yellow]    = { 0.87, 0.87, 0.42 },
    [colors.red]       = { 0.80, 0.30, 0.30 },
    [colors.gray]      = { 0.30, 0.30, 0.30 },
    [colors.lightGray] = { 0.60, 0.60, 0.60 },
    [colors.cyan]      = { 0.30, 0.60, 0.70 },
    [colors.blue]      = { 0.20, 0.35, 0.80 },
    [colors.lime]      = { 0.50, 0.80, 0.10 },
    [colors.black]     = { 0.07, 0.07, 0.07 },
  },
}

--- A tela aceita mexer na paleta?
local function podeMexer(tela)
  if not tela then return false end
  if type(tela.setPaletteColour) ~= "function" then return false end
  if tela.isColour and not tela.isColour() then return false end
  return true
end
palette.podeMexer = podeMexer

--- Le as cores atuais da tela para poder devolver do jeito que estavam.
-- Devolve nil se a tela nao mexe em paleta - e nil e aceito por restaurar().
function palette.guardar(tela)
  if not podeMexer(tela) then return nil end
  local estado = {}
  for _, cor in ipairs(MEXIDAS) do
    local ok, r, g, b = pcall(tela.getPaletteColour, cor)
    if ok and type(r) == "number" then estado[cor] = { r, g, b } end
  end
  return estado
end

--- Devolve as cores exatamente como estavam quando guardar() rodou.
-- Nao assume o padrao do CC: outro programa pode ter mexido antes de nos.
function palette.restaurar(tela, estado)
  if not estado or not podeMexer(tela) then return end
  for cor, rgb in pairs(estado) do
    pcall(tela.setPaletteColour, cor, rgb[1], rgb[2], rgb[3])
  end
end

function palette.aplicar(tela, paleta)
  if not paleta or not podeMexer(tela) then return end
  for cor, rgb in pairs(paleta) do
    pcall(tela.setPaletteColour, cor, rgb[1], rgb[2], rgb[3])
  end
end

--- Interpola duas paletas. t de 0 (de) a 1 (para).
function palette.tween(tela, de, para, t)
  if not podeMexer(tela) then return end
  t = math.max(0, math.min(1, t or 0))
  for cor, a in pairs(de) do
    local b = para[cor]
    if b then
      pcall(tela.setPaletteColour, cor,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t,
            a[3] + (b[3] - a[3]) * t)
    end
  end
end

--- Roda uma funcao com a paleta livre e devolve as cores no fim, aconteca o
-- que acontecer - inclusive erro ou Ctrl+T. Este e o jeito recomendado.
-- Devolve os mesmos valores de pcall: ok, resultado-ou-erro.
function palette.com(tela, fn)
  local antes = palette.guardar(tela)
  local ok, r = pcall(fn)
  palette.restaurar(tela, antes)
  return ok, r
end

return palette]=]
ARQUIVOS["rendimento.lua"] = [=[
--[[ rendimento - quanto do possivel o sistema esta tirando

  "100%" nominal nao existe na pratica. Os numeros de catalogo do painel valem
  em STC (1000 W/m2 perpendicular, celula a 25 graus). No jogo o sol anda pelo
  ceu, a celula esquenta (NOCT 45), e parte da luz e difusa (12%) e de albedo
  (8%). Mesmo perfeitamente alinhado o painel fica abaixo do nominal.

  Por isso aqui ha DUAS referencias:

    empirica  o melhor que este sistema ja produziu, guardado em disco.
              E a referencia honesta: diz se voce esta tirando hoje o que
              ja tirou antes. Comeca a valer depois de alguns dias de sol.

    nominal   paineis x potencia de catalogo. So aparece se voce disser
              quantos paineis tem. Serve para saber a ordem de grandeza,
              nunca para esperar 100%.

  Os valores de catalogo abaixo sao os do powergrid-server.toml deste perfil.
  Se voce mexer na config do mod, ajuste aqui tambem.
]]

local rendimento = {}

local ARQUIVO = ".helios_pico"

-- catalogo do painel, de powergrid-server.toml
rendimento.PAINEL = {
  voc = 26.4,     -- tensao de circuito aberto
  isc = 3.3,      -- corrente de curto
  vmp = 21.12,    -- tensao no ponto de maxima potencia
  imp = 3.036,    -- corrente no ponto de maxima potencia
}

--- Potencia de catalogo de um painel, em W (STC).
function rendimento.porPainel()
  return rendimento.PAINEL.vmp * rendimento.PAINEL.imp
end

--- Maximo nominal para N paineis, na grandeza pedida.
-- unidade = "W" (potencia) ou "A" (corrente). nil se nao souber quantos.
function rendimento.nominal(paineis, unidade)
  paineis = tonumber(paineis) or 0
  if paineis <= 0 then return nil end
  if unidade == "A" then
    -- em serie a corrente nao soma; em paralelo soma. Assumimos paralelo,
    -- que e o caso do multibloco de paineis do mod.
    return paineis * rendimento.PAINEL.imp
  end
  return paineis * rendimento.porPainel()
end

-- ------------------------------------------------------------------ historico

--- Le o pico ja registrado. Devolve nil se nunca houve.
function rendimento.picoSalvo()
  if not fs.exists(ARQUIVO) then return nil end
  local f = fs.open(ARQUIVO, "r")
  if not f then return nil end
  local linha = f.readLine()
  f.close()
  return tonumber(linha)
end

--- Guarda um pico novo, se for maior que o anterior. Devolve o pico valendo.
function rendimento.registrar(valor)
  if type(valor) ~= "number" or valor ~= valor then return rendimento.picoSalvo() end
  local antigo = rendimento.picoSalvo()
  if antigo and valor <= antigo then return antigo end
  local f = fs.open(ARQUIVO, "w")
  if f then f.write(tostring(valor)); f.close() end
  return valor
end

function rendimento.esquecer()
  if fs.exists(ARQUIVO) then fs.delete(ARQUIVO) end
end

-- ---------------------------------------------------------------- avaliacao

--- Como esta indo agora.
-- Devolve { pctPico =, pctNominal =, pico =, nominal =, texto = }
-- pctPico e nil enquanto nao houver historico suficiente.
function rendimento.avaliar(atual, paineis, unidade)
  local r = {}
  r.pico = rendimento.picoSalvo()
  r.nominal = rendimento.nominal(paineis, unidade)

  if r.pico and r.pico > 0 then
    r.pctPico = atual / r.pico * 100
  end
  if r.nominal and r.nominal > 0 then
    r.pctNominal = atual / r.nominal * 100
  end

  if not r.pctPico then
    r.texto = "aprendendo o maximo"
  elseif r.pctPico >= 97 then
    r.texto = "no melhor ja visto"
  elseif r.pctPico >= 85 then
    r.texto = "perto do melhor"
  elseif r.pctPico >= 45 then
    -- meia geracao de manha ou no fim da tarde e o normal do dia, nao
    -- sinal de problema: o limiar do alarme fica mais embaixo
    r.texto = "abaixo do melhor"
  else
    r.texto = "bem abaixo"
  end

  return r
end

--- Motivos plausiveis para estar abaixo do pico, do mais provavel ao menos.
-- Nao adivinha: usa a hora do jogo e a carga da bateria, que sao coisas que
-- derrubam a geracao sem o painel ter saido do lugar.
function rendimento.porque(r, ehDia, bateriaPct)
  if not r.pctPico or r.pctPico >= 85 then return nil end
  if not ehDia then return "e noite" end
  if bateriaPct and bateriaPct >= 95 then
    return "bateria cheia: a tensao dela subiu e a corrente caiu"
  end
  local h = os.time()
  if h < 8 or h > 16 then
    return "sol baixo no ceu: o maximo do dia e perto do meio-dia"
  end
  if bateriaPct and bateriaPct >= 80 then
    return "bateria quase cheia, a corrente cai naturalmente"
  end
  return "pode ser nuvem, chuva, ou o painel desalinhado"
end

return rendimento]=]
ARQUIVOS["clima.lua"] = [=[
--[[ clima - aprende a curva do dia e infere a condicao do ceu

  Nenhum mod deste perfil expoe o clima ao computador: nao existe sensor de
  chuva. O unico sensor disponivel e o proprio painel.

  Entao o sistema aprende: para cada hora do dia guarda a MAIOR geracao ja
  vista naquela hora. Isso vira a curva de um dia limpo. Comparando o agora
  com a curva, da para separar tres coisas que baixam a geracao:

    sol baixo no ceu   a curva ja preve; nao e anomalia
    nublado            metade do esperado para aquela hora
    chuva              bem abaixo do esperado para aquela hora

  LIMITE HONESTO: isto nao distingue chuva de painel quebrado, obstruido ou
  fio solto. Diz "esta gerando muito abaixo do que costuma nesta hora" - a
  causa mais provavel e o tempo, mas nao e a unica.

  A curva so vale depois de alguns dias de sol. Ate la, avaliar() devolve
  "aprendendo" em vez de inventar diagnostico.
]]

local clima = {}

local CURVA = ".helios_curva"
local DIARIO = ".helios_dias"

--- Hora do jogo como inteiro de 0 a 23.
function clima.hora()
  return math.floor(os.time()) % 24
end

-- ------------------------------------------------------------------- curva

--- Le a curva do disco. Devolve tabela hora -> maior geracao vista.
function clima.curva()
  local c = {}
  if not fs.exists(CURVA) then return c end
  local f = fs.open(CURVA, "r")
  if not f then return c end
  for linha in f.readLine do
    local h, v = linha:match("^(%d+)=([%d%.eE%+%-]+)$")
    if h then c[tonumber(h)] = tonumber(v) end
  end
  f.close()
  return c
end

local function gravarCurva(c)
  local f = fs.open(CURVA, "w")
  if not f then return end
  for h = 0, 23 do
    if c[h] then f.write(h .. "=" .. tostring(c[h]) .. "\n") end
  end
  f.close()
end

--- Registra uma leitura. So sobe o maximo daquela hora, nunca desce:
-- a curva representa o melhor caso, o dia limpo.
function clima.registrar(valor, hora)
  if type(valor) ~= "number" or valor ~= valor or valor <= 0 then return end
  hora = hora or clima.hora()
  local c = clima.curva()
  if not c[hora] or valor > c[hora] then
    c[hora] = valor
    gravarCurva(c)
  end
end

--- Quantas horas do dia ja tem referencia. Abaixo de 4, nao da para julgar.
function clima.maturidade()
  local n = 0
  for _ in pairs(clima.curva()) do n = n + 1 end
  return n
end

--- Quanto se espera nesta hora, pela curva aprendida.
-- Se a hora exata nao tem registro, usa a media das vizinhas.
function clima.esperado(hora)
  hora = hora or clima.hora()
  local c = clima.curva()
  if c[hora] then return c[hora] end
  local antes, depois = c[(hora - 1) % 24], c[(hora + 1) % 24]
  if antes and depois then return (antes + depois) / 2 end
  return antes or depois
end

-- ---------------------------------------------------------------- avaliacao

--- Classifica o ceu agora.
-- Devolve { condicao =, pct =, esperado =, texto = }
-- condicao: "aprendendo" | "noite" | "limpo" | "nublado" | "chuva"
function clima.avaliar(atual, ehDia)
  local r = { esperado = clima.esperado() }

  if ehDia == false then
    r.condicao, r.texto = "noite", "noite"
    return r
  end

  if clima.maturidade() < 4 or not r.esperado or r.esperado <= 0 then
    r.condicao, r.texto = "aprendendo", "aprendendo a curva do dia"
    return r
  end

  r.pct = atual / r.esperado * 100

  if r.pct >= 70 then
    r.condicao, r.texto = "limpo", "ceu limpo"
  elseif r.pct >= 25 then
    r.condicao, r.texto = "nublado", "nublado"
  else
    r.condicao, r.texto = "chuva", "chovendo, provavelmente"
  end
  return r
end

--- Girar o painel resolve o que esta acontecendo agora?
-- Com chuva ou nublado pesado, nao: o problema esta no ceu, nao no angulo.
function clima.valeGirar(r)
  if not r then return true end
  return r.condicao ~= "chuva"
end

-- ------------------------------------------------------------ fecho do dia

--- Guarda o resumo de um dia. Mantem os ultimos 14.
function clima.fecharDia(resumo)
  local dias = clima.dias()
  table.insert(dias, resumo)
  while #dias > 14 do table.remove(dias, 1) end

  local f = fs.open(DIARIO, "w")
  if not f then return end
  for _, d in ipairs(dias) do
    f.write(string.format("%s;%.4f;%.4f;%d;%s\n",
            d.data or "?", d.pico or 0, d.medio or 0,
            d.amostras or 0, d.condicao or "?"))
  end
  f.close()
end

--- Le os dias guardados, do mais antigo ao mais novo.
function clima.dias()
  local dias = {}
  if not fs.exists(DIARIO) then return dias end
  local f = fs.open(DIARIO, "r")
  if not f then return dias end
  for linha in f.readLine do
    local data, pico, medio, n, cond = linha:match("^([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")
    if data then
      dias[#dias + 1] = {
        data = data, pico = tonumber(pico) or 0,
        medio = tonumber(medio) or 0,
        amostras = tonumber(n) or 0, condicao = cond,
      }
    end
  end
  f.close()
  return dias
end

--- Compara o ultimo dia fechado com a media dos anteriores.
-- Devolve nil se nao houver dias suficientes para comparar.
function clima.tendencia()
  local dias = clima.dias()
  if #dias < 2 then return nil end
  local ultimo = dias[#dias]
  local soma, n = 0, 0
  for i = 1, #dias - 1 do
    soma = soma + dias[i].medio
    n = n + 1
  end
  if n == 0 or soma == 0 then return nil end
  local media = soma / n
  return {
    ultimo = ultimo,
    media = media,
    pct = ultimo.medio / media * 100,
  }
end

function clima.esquecer()
  if fs.exists(CURVA) then fs.delete(CURVA) end
  if fs.exists(DIARIO) then fs.delete(DIARIO) end
end

return clima]=]
ARQUIVOS["circuito.lua"] = [=[
--[[ circuito - o diagrama vivo do sistema solar

  Desenha os quatro blocos reais (bearing, medidor, bateria, computador) com a
  energia correndo pelas linhas. A velocidade dos pontos acompanha a corrente
  medida: sem geracao, eles param. Da para saber como o sistema esta sem ler
  numero nenhum.

  As formas saem pelo framebuffer de subpixel; os rotulos e numeros vao por
  cima, como texto normal, depois do enviar().

    circuito.desenhar(fb, tela, dados, fase)

  dados = {
    geracao    = numero,        -- corrente ou potencia lida
    unidade    = "A" | "W",
    pico       = numero,        -- melhor do dia, para a barra
    bateriaPct = numero | nil,
    estado     = "texto curto",
    girando    = boolean,
  }
]]

local circuito = {}

--- Posicao dos blocos, em pontos, proporcional ao tamanho da tela.
local function layout(fb)
  local L = {}
  L.cw = math.floor(fb.w * 0.19)
  L.chh = math.floor(fb.h * 0.20)
  L.y = math.floor(fb.h * 0.16)
  L.bearing = { x = math.floor(fb.w * 0.04), y = L.y }
  L.medidor = { x = math.floor(fb.w * 0.40), y = L.y }
  L.bateria = { x = math.floor(fb.w * 0.76), y = L.y }
  L.pc      = { x = math.floor(fb.w * 0.40), y = math.floor(fb.h * 0.60) }
  L.retorno = math.floor(fb.h * 0.46)
  return L
end

local function caixa(fb, b, L, cor)
  fb:retangulo(b.x, b.y, L.cw, L.chh, cor, false)
end

--- Pontos correndo ao longo de um segmento reto.
-- fase avanca com o tempo; espaco e a distancia entre pontos.
local function fluxo(fb, x1, y1, x2, y2, fase, cor, espaco)
  espaco = espaco or 6
  local dx, dy = x2 - x1, y2 - y1
  local comp = math.sqrt(dx * dx + dy * dy)
  if comp < 1 then return end
  local n = math.floor(comp / espaco)
  for i = 0, n do
    local d = (i * espaco + fase) % comp
    local t = d / comp
    fb:ponto(x1 + dx * t, y1 + dy * t, cor)
    fb:ponto(x1 + dx * t, y1 + dy * t + 1, cor)
  end
end

--- Desenha tudo. Chama fb:enviar() e depois escreve os rotulos por cima.
function circuito.desenhar(fb, tela, dados, fase)
  local L = layout(fb)
  local cw, ch = tela.getSize()
  local ger = dados.geracao or 0
  local viva = ger > 0.001

  fb:limpar(colors.black)

  local corLinha = viva and colors.lime or colors.gray
  local corFluxo = viva and colors.yellow or colors.gray

  -- caixas
  caixa(fb, L.bearing, L, colors.cyan)
  caixa(fb, L.medidor, L, colors.orange)
  caixa(fb, L.bateria, L, colors.lightGray)
  caixa(fb, L.pc, L, colors.white)

  -- bateria enchendo por dentro
  if dados.bateriaPct then
    local p = math.max(0, math.min(100, dados.bateriaPct))
    local alturaUtil = L.chh - 4
    local cheio = math.floor(alturaUtil * p / 100)
    local cor = colors.lime
    if p < 25 then cor = colors.red elseif p < 60 then cor = colors.orange end
    if cheio > 0 then
      fb:retangulo(L.bateria.x + 2, L.bateria.y + 2 + (alturaUtil - cheio),
                   L.cw - 4, cheio, cor, true)
    end
  end

  -- linhas do circuito
  local meioY = L.y + math.floor(L.chh / 2)
  local bDir = L.bearing.x + L.cw
  local mEsq = L.medidor.x
  local mDir = L.medidor.x + L.cw
  local baEsq = L.bateria.x

  fb:linha(bDir, meioY, mEsq, meioY, corLinha)
  fb:linha(mDir, meioY, baEsq, meioY, corLinha)

  -- retorno por baixo, fechando o laco
  local baMeio = L.bateria.x + math.floor(L.cw / 2)
  local beMeio = L.bearing.x + math.floor(L.cw / 2)
  local baBase = L.bateria.y + L.chh
  local beBase = L.bearing.y + L.chh
  fb:linha(baMeio, baBase, baMeio, L.retorno, corLinha)
  fb:linha(baMeio, L.retorno, beMeio, L.retorno, corLinha)
  fb:linha(beMeio, L.retorno, beMeio, beBase, corLinha)

  -- energia correndo. quanto mais corrente, mais rapido.
  if viva then
    local vel = fase * (1 + math.min(4, ger / math.max(0.001, dados.pico or ger)) * 3)
    fluxo(fb, bDir, meioY, mEsq, meioY, vel, corFluxo)
    fluxo(fb, mDir, meioY, baEsq, meioY, vel, corFluxo)
    fluxo(fb, baMeio, L.retorno, beMeio, L.retorno, -vel, corFluxo)
  end

  -- cabo de dados ate o computador (tracejado curto)
  local pcTopo = L.pc.y
  local pcMeio = L.pc.x + math.floor(L.cw / 2)
  local mBase = L.medidor.y + L.chh
  for y = mBase, pcTopo, 3 do
    fb:ponto(pcMeio, y, colors.blue)
  end

  fb:enviar()

  -- ------------------------------------------------------- rotulos por cima

  local function txt(px, py, s, cor)
    -- converte ponto -> celula
    local cx = math.floor((px - 1) / 2) + 1
    local cy = math.floor((py - 1) / 3) + 1
    if cy < 1 or cy > ch then return end
    cx = math.max(1, math.min(cw - #s + 1, cx))
    tela.setTextColor(cor or colors.white)
    tela.setBackgroundColor(colors.black)
    tela.setCursorPos(cx, cy)
    tela.write(s)
  end

  local function rotulo(b, nome, valor, corValor)
    txt(b.x + 3, b.y + 3, nome, colors.white)
    if valor then txt(b.x + 3, b.y + math.floor(L.chh / 2) + 2, valor, corValor) end
  end

  local u = dados.unidade or ""
  rotulo(L.bearing, "PAINEL", dados.girando and "girando" or "parado",
         dados.girando and colors.yellow or colors.gray)
  rotulo(L.medidor, "MEDIDOR", string.format("%.2f %s", ger, u), colors.yellow)
  rotulo(L.bateria, "BATERIA",
         dados.bateriaPct and string.format("%.0f%%", dados.bateriaPct) or "--",
         colors.white)
  rotulo(L.pc, "HELIOS", dados.estado, colors.cyan)

  -- areas clicaveis, em CELULAS, para quem trata monitor_touch
  local function area(b, nome)
    return {
      nome = nome,
      x1 = math.floor((b.x - 1) / 2) + 1,
      y1 = math.floor((b.y - 1) / 3) + 1,
      x2 = math.floor((b.x + L.cw - 1) / 2) + 1,
      y2 = math.floor((b.y + L.chh - 1) / 3) + 1,
    }
  end
  return {
    area(L.bearing, "painel"),
    area(L.medidor, "medidor"),
    area(L.bateria, "bateria"),
    area(L.pc,      "helios"),
  }
end

--- Qual area foi tocada, se alguma.
function circuito.tocou(areas, x, y)
  if not areas then return nil end
  for _, a in ipairs(areas) do
    if x >= a.x1 and x <= a.x2 and y >= a.y1 and y <= a.y2 then return a.nome end
  end
  return nil
end

return circuito]=]
ARQUIVOS["boot.lua"] = [=[
--[[ boot - a animacao do amanhecer do HELIOS

  O sol nao e redesenhado a cada quadro para fazer o fade: ele e desenhado e a
  PALETA muda. Sao 10 chamadas por quadro em vez de repintar a tela inteira.

  boot.rodar(tela, modo)   modo = "completo" (~5s) ou "curto" (~1,5s)
  boot.jaViu()             ja mostrou a versao completa neste computador?
  boot.marcarVisto()

  Qualquer tecla pula. Quem chama e responsavel por nao deixar um vigia de
  tecla vivo depois disso - senao ele rouba a primeira tecla do menu.
]]

local boot = {}

local ARQUIVO = ".helios_boot"

function boot.jaViu()
  return fs.exists(ARQUIVO)
end

function boot.marcarVisto()
  if fs.exists(ARQUIVO) then return end
  local f = fs.open(ARQUIVO, "w")
  if f then f.write("visto"); f.close() end
end

--- Esquece que ja viu, para poder rever a animacao completa.
function boot.esquecer()
  if fs.exists(ARQUIVO) then fs.delete(ARQUIVO) end
end

--- Roda a animacao. Devolve true se foi ate o fim, false se pularam.
-- A paleta e restaurada aqui dentro, em qualquer caminho de saida.
function boot.rodar(tela, modo, pixel, palette)
  local fb = pixel.novo(tela)
  local cw, ch = tela.getSize()
  local P = palette.PALETAS

  local curto  = (modo == "curto")
  local passos = curto and 12 or 34
  local espera = curto and 0.05 or 0.08

  local solX = math.floor(fb.w / 2)
  local raio = math.max(3, math.floor(math.min(fb.w, fb.h) / 7))
  local chao = fb.h - math.floor(fb.h / 5)
  local altoY = math.floor(fb.h * 0.34)

  -- estrelas fixas: sorteadas uma vez, para nao piscarem entre quadros
  local estrelas = {}
  for _ = 1, math.floor(fb.w * fb.h / 110) do
    estrelas[#estrelas + 1] = {
      math.random(1, fb.w),
      math.random(1, math.floor(fb.h * 0.55)),
    }
  end

  local pulou = false

  local function cena(solY, fase)
    fb:limpar(colors.black)

    for _, e in ipairs(estrelas) do
      if e[2] < solY - raio - 2 then fb:ponto(e[1], e[2], colors.gray) end
    end

    -- raios: dois tracos por direcao, para terem corpo
    local comp = raio + 3 + math.floor(math.sin(fase) * 2 + 2)
    for i = 0, 11 do
      local a = (i / 12) * math.pi * 2 + fase * 0.12
      local ca, sa = math.cos(a), math.sin(a)
      fb:linha(solX + ca * (raio + 2), solY + sa * (raio + 2),
               solX + ca * comp,       solY + sa * comp, colors.yellow)
      fb:linha(solX + ca * (raio + 2) + 1, solY + sa * (raio + 2),
               solX + ca * comp + 1,       solY + sa * comp, colors.orange)
    end

    fb:circulo(solX, solY, raio, colors.orange, true)
    fb:circulo(solX, solY, math.max(1, raio - 2), colors.yellow, true)

    fb:linha(1, chao, fb.w, chao, colors.gray)
    fb:enviar()
  end

  local function texto(y, s, cor)
    if y < 1 or y > ch then return end
    tela.setTextColor(cor or colors.white)
    tela.setBackgroundColor(colors.black)
    tela.setCursorPos(math.max(1, math.floor((cw - #s) / 2) + 1), y)
    tela.write(s)
  end

  local function animar()
    for i = 0, passos do
      local t = i / passos
      local solY = math.floor(chao - (chao - altoY) * t)

      if t < 0.5 then
        palette.tween(tela, P.noite, P.amanhecer, t * 2)
      else
        palette.tween(tela, P.amanhecer, P.dia, (t - 0.5) * 2)
      end

      cena(solY, i * 0.4)
      sleep(espera)
    end

    texto(math.floor(ch / 2),     "H E L I O S", colors.white)
    texto(math.floor(ch / 2) + 2, "controle solar e energia", colors.lightGray)
    sleep(curto and 0.3 or 0.9)
  end

  local function vigia()
    os.pullEvent("key")
    pulou = true
  end

  -- a paleta e global: sai daqui com as cores como estavam, sempre
  palette.com(tela, function()
    parallel.waitForAny(animar, vigia)
  end)

  return not pulou
end

return boot]=]
ARQUIVOS["pgmon.lua"] = [=[
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

local pgapi  = loadLib("pgapi")
local config = loadLib("config")

local REFRESH  = 0.5   -- segundos entre leituras
local HIST_MAX = 300   -- amostras guardadas do historico de potencia

-- ------------------------------------------------------------------- display

local args = { ... }
local cfg = config.ler()
local scan = pgapi.scan()

local monitorEscolhido = pgapi.escolherMonitor(scan, cfg.monitor)

local out, isMonitor
if monitorEscolhido then
  out, isMonitor = monitorEscolhido.dev, true
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
print("pgmon encerrado.")]=]
ARQUIVOS["suntrack.lua"] = [=[
--[[ suntrack - rastreador solar automatico para PowerGrid + Create

  O QUE FAZ
    Gira o Solar Panel Bearing procurando o angulo que mais gera energia e
    fica corrigindo ao longo do dia conforme o sol anda. De noite trava o
    painel e volta a procurar no amanhecer.

  COMO O BEARING FUNCIONA
    O Solar Panel Bearing CONSOME torque do Create e PRODUZ eletricidade
    (a geracao dos paineis montados nele). Ou seja: para girar o painel o
    computador nao mexe em eletricidade nenhuma - ele controla a rotacao
    do Create, com redstone.

    Embreagem (Clutch):  sinal de redstone -> para de transmitir rotacao.
    Cambio (Gearshift):  sinal de redstone -> inverte o sentido.

  REDSTONE PELA REDE
    Clutch e Gearshift do Create nao sao perifericos - um Wired Modem colado
    neles nao expoe nada ao computador. O que os alcanca de longe e o
    Redstone Relay do proprio CC:Tweaked: um bloco com Wired Modem que leva
    redstone pela mesma rede de cabo do medidor. Cole um relay em cada bloco
    (ou um so, se os dois estiverem perto) e rode 'configurar' para dizer
    qual relay e qual lado e cada coisa. Sem relay, ainda da para usar o
    redstone nativo do computador (rele "computador"), mas ai a embreagem
    precisa estar encostada nele ou ligada por fio de redstone comum.

  MONTAGEM
    1. Uma fonte de rotacao do Create (motor, moinho, o que preferir).
       Use RPM BAIXO - 8 a 16. Em RPM alto o menor pulso ja passa do ponto.
    2. Gearshift no eixo (opcional, mas recomendado) - inverte o sentido.
    3. Clutch no eixo, depois do gearshift - liga e desliga a rotacao.
    4. O eixo entra no Solar Panel Bearing, que gira os paineis.
    5. Um medidor no circuito eletrico do bearing, ligado por Wired Modem +
       Networking Cable. Prefira o CURRENT GAUGE: ele tem 2 terminais e vai
       em serie, enquanto o Power Gauge tem 3 (shunt em serie + referencia
       de tensao). Para rastrear o sol a corrente serve tao bem quanto a
       potencia - num painel solar ela acompanha a irradiancia quase
       proporcionalmente.

       O medidor tem terminal + e -, e vai EM SERIE: a corrente entra
       pelo + e sai pelo -. A cadeia fica assim:

         bearing +  ->  gauge +
         gauge -    ->  bateria +
         bateria -  ->  bearing -

       O circuito precisa estar FECHADO, com uma carga (bateria, resistor,
       lampada) no caminho de volta ao bearing. Sem carga nao circula
       corrente e o medidor le zero. Ligar os dois terminais do gauge no
       mesmo polo e curto-circuito - o gauge tem resistencia quase zero e
       queima.
    6. Redstone Relay + Wired Modem colado na embreagem, e outro no cambio
       (ou reaproveite o mesmo relay se dois lados dele alcancarem os dois
       blocos). Ligue ambos na mesma rede de cabo do medidor.

  ATENCAO AO ESTADO SEGURO
    O Clutch do Create para quando RECEBE redstone. Entao, com o computador
    desligado, o padrao e o painel girar sem parar. Se isso incomodar, ponha
    uma tocha de redstone invertendo o sinal entre o rele e o clutch, e marque
    "ha uma tocha invertendo o sinal" em 'configurar' - ai "computador
    desligado" passa a significar "painel travado".

  USO
    configurar           assistente que descobre a rede e escreve helios.cfg
    suntrack testar       confere a montagem - rode depois de configurar
    suntrack              roda o rastreador
    suntrack varrer        da uma volta medindo e mostra o pico
    suntrack parar         trava o painel e sai
    Tecla Q encerra e trava o painel.
]]

local function loadLib(name)
  local ok, lib = pcall(require, name)
  if ok and type(lib) == "table" then return lib end
  local dir = fs.getDir(shell.getRunningProgram())
  local p = fs.combine(dir, name .. ".lua")
  if fs.exists(p) then return dofile(p) end
  error("Falta a biblioteca " .. name .. ".lua (coloque na mesma pasta)", 0)
end

local pgapi   = loadLib("pgapi")
local uilib   = loadLib("ui")
local clima   = loadLib("clima")
local config  = loadLib("config")

-- ------------------------------------------------------------------ ajustes

local cfg, origemCfg, avisoCfg = config.ler()
local R = cfg.rastreio

local temCambio = cfg.cambio.rele ~= config.NENHUM

-- ------------------------------------------------------------------ hardware

local scan = pgapi.scan()
local meterList, meterKind, meterUnit = pgapi.escolherMedidor(scan, cfg.medidor)
local medidorFraco = (meterKind == "voltage")

local function abortar(msg)
  print()
  printError(msg)
  print()
  print("Perifericos vistos agora:")
  local n = 0
  for _, name in ipairs(peripheral.getNames()) do
    print("  " .. name .. "  (" .. peripheral.getType(name) .. ")")
    n = n + 1
  end
  if n == 0 then print("  (nenhum)") end
  error("", 0)
end

if #meterList == 0 then
  if cfg.medidor ~= config.AUTO and cfg.medidor ~= "" then
    abortar("O medidor configurado (\"" .. cfg.medidor .. "\") nao foi encontrado.\n" ..
            "Rode 'configurar' de novo para escolher outro.")
  end
  abortar("Nao achei medidor nenhum (power, current ou voltage gauge).\n" ..
          "Preciso de um no circuito do bearing para saber se melhorou.\n" ..
          "Ligue um com Wired Modem + cabo, e clique no modem para ativar.")
end

if avisoCfg then
  print("aviso: " .. avisoCfg)
end

--- Potencia (ou corrente) somada de todos os medidores.
-- Em valor absoluto de proposito: o medidor tem terminal + e -, e se ele
-- estiver montado ao contrario a leitura vem negativa. Sem o abs, nenhuma
-- leitura passaria de best=0 e o rastreador acharia que nunca melhora.
-- O que importa aqui e a intensidade, nao o sentido da corrente.
local function readNow()
  local sum = 0
  for _, e in ipairs(meterList) do
    local g = pgapi.readGauge(e, meterKind)
    if g then sum = sum + math.abs(g.value) end
  end
  return sum
end

--- Carga da bateria mais cheia da rede, em %, ou nil se nao houver bateria.
local function cargaBateria()
  local maior
  for _, e in ipairs(scan.battery) do
    local b = pgapi.readBattery(e)
    if b and b.pct then maior = math.max(maior or 0, b.pct) end
  end
  return maior
end

--- A bateria e uma fonte de tensao, e a tensao dela sobe conforme carrega.
-- Quando enche, a diferenca de tensao contra o painel some e a corrente cai
-- quase a zero. Sem esta checagem o rastreador leria isso como desalinho e
-- passaria o resto do dia girando atras de uma corrente que nao volta.
local cheiaAgora = false
local function bateriaCheia()
  local carga = cargaBateria()
  if not carga then return false end
  local limite = cheiaAgora and R.bateriaRetoma or R.bateriaCheia
  cheiaAgora = carga >= limite
  return cheiaAgora
end

--- Media de varias leituras, para nao decidir em cima de ruido.
local function measure()
  local sum = 0
  for i = 1, R.amostras do
    sum = sum + readNow()
    if i < R.amostras then sleep(R.intervaloAmostra) end
  end
  return sum / R.amostras
end

-- ------------------------------------------------------------------- motor

local function motorStop()
  config.setNivel(cfg.embreagem, 15)   -- sinal cheio trava
end

local function motorStart(dir)
  if temCambio then config.setBool(cfg.cambio, dir < 0) end
  config.setNivel(cfg.embreagem, cfg.embreagem.nivelGiro)
end

--- Um passo de rotacao: solta, espera, trava, deixa assentar.
local function step(dir, dur)
  motorStart(dir)
  sleep(dur or R.pulso)
  motorStop()
  sleep(R.assentar)
end

-- deixar o painel girando depois que o programa morre seria pessimo
local function comCleanup(fn)
  local ok, err = pcall(fn)
  motorStop()
  if not ok and err and err ~= "" and err ~= "Terminated" then
    printError(err)
  end
end

-- ---------------------------------------------------------------------- ui

local state, detail = "iniciando", ""
local ultimaBusca = -math.huge
local ceu                      -- ultima avaliacao do ceu
local diaSoma, diaN, diaPico = 0, 0, 0
local diaFechado = false
local best, current, dir = 0, 0, 1

local tela = uilib.tela(term.current())
local UC = tela.C

local function corDaFracao(f)
  if f >= 0.9 then return UC.bom end
  if f >= 0.7 then return UC.atencao end
  return UC.ruim
end

local function desenhar()
  tela:limpar()
  tela:cabecalho("suntrack", pgapi.gameClock() ..
                 (pgapi.isDaytime() and " dia" or " noite"))

  tela:texto(2, 3, "estado", UC.fraco)
  tela:texto(11, 3, state, UC.destaque)
  if detail ~= "" then tela:texto(11, 4, detail, UC.fraco) end

  -- geracao atual, com barra relativa ao melhor do dia
  local frac = (best > 0) and (current / best) or 0
  tela:linha(6, "agora", pgapi.fmt(current, meterUnit), UC.acento)
  tela:barra(2, 7, tela.w - 2, frac * 100, corDaFracao(frac))
  tela:linha(8, "melhor hoje", pgapi.fmt(best, meterUnit))

  tela:linha(10, "sentido", (dir > 0 and "->" or "<-") ..
             (temCambio and "" or "  (so um)"))
  tela:linha(11, "embreagem", config.descrever(cfg.embreagem) ..
             (cfg.embreagem.analogica and "  analog" or ""))
  tela:linha(12, "cambio", config.descrever(cfg.cambio))

  local nome = meterList[1].name
  if #meterList > 1 then nome = nome .. " +" .. (#meterList - 1) end
  tela:linha(13, "medidor", nome)

  if ceu and ceu.texto then
    tela:linha(14, "ceu", ceu.texto ..
               (ceu.pct and string.format("  %.0f%%", ceu.pct) or ""),
               ceu.condicao == "chuva" and UC.ruim
               or ceu.condicao == "nublado" and UC.atencao or UC.bom)
  end

  local carga = cargaBateria()
  if carga then
    tela:linha(15, "bateria", string.format("%.0f%%", carga),
               carga >= R.bateriaCheia and UC.atencao or UC.bom)
  end

  if medidorFraco then
    tela:texto(2, 17, "! tensao quase nao muda com a luz", UC.atencao)
    tela:texto(2, 18, "  so serve com carga resistiva fixa", UC.fraco)
  end

  tela:rodape(" q encerra e trava o painel ")
  tela:mostrar()
end

local function setState(s, d)
  state, detail = s, d or ""
  desenhar()
end

-- ------------------------------------------------------------------ varredura

--- Gira continuamente medindo, e devolve o pico visto.
local function sweep()
  setState("varrendo", "procurando o maximo dando uma volta")
  local peak = 0
  local t0 = os.clock()
  motorStart(dir)
  while os.clock() - t0 < R.volta do
    current = readNow()
    if current > peak then peak = current end
    best = peak
    desenhar()
    sleep(0.2)
  end
  motorStop()
  sleep(R.assentar)
  return peak
end

--- Continua girando ate a geracao chegar perto do pico conhecido.
local function goToPeak(peak, tol)
  tol = tol or 0.95
  setState("posicionando", string.format("indo para %.0f%% do pico", tol * 100))
  local limit = os.clock() + R.volta * 1.5
  while os.clock() < limit do
    current = measure()
    if current >= peak * tol then
      best = current
      return true
    end
    step(dir)
    desenhar()
  end
  return false
end

-- ------------------------------------------------------- perturb and observe

local function refine()
  local before = measure()
  step(dir)
  local after = measure()
  current = after

  if after < before * (1 - R.bandaMorta) then
    if temCambio then
      dir = -dir
      setState("ajustando", "piorou, invertendo o sentido")
    else
      -- sem cambio nao da para voltar: segue em frente e da a volta
      setState("ajustando", "piorou, seguindo ate dar a volta")
    end
  else
    setState("ajustando", "seguindo")
  end

  if after > best then best = after end
  return after
end

-- ------------------------------------------------------------------ programa

local args = { ... }
local cmd = args[1]

if cmd == "lados" then
  print("O comando 'lados' virou parte do assistente.")
  print("Rode 'configurar' - ele testa os lados e ja salva a escolha.")
  return
end

if cmd == "parar" then
  motorStop()
  print("Painel travado (" .. config.descrever(cfg.embreagem) .. ").")
  return
end

if cmd == "testar" then
  term.clear()
  term.setCursorPos(1, 1)
  print("=== teste de montagem ===")
  print()
  print("embreagem: " .. config.descrever(cfg.embreagem) ..
        (cfg.embreagem.analogica and " (analogica)" or ""))
  print("cambio:    " .. config.descrever(cfg.cambio))
  for _, e in ipairs(meterList) do print("medidor:   " .. e.name) end
  if not config.saidaOk(cfg.embreagem) then
    print()
    print("aviso: o rele da embreagem nao foi encontrado na rede agora.")
  end
  print()

  motorStop()
  sleep(1)
  local parado = measure()
  print("travado, gerando " .. pgapi.fmt(parado, meterUnit))
  if parado <= 0 then
    print("  aviso: o medidor esta lendo zero.")
    print("  E de noite? O medidor esta na saida do bearing?")
  end
  print()
  print("Solto agora - olhe o painel, ele deve girar.")

  local minv, maxv = parado, parado
  local fim = false
  comCleanup(function()
    motorStart(1)
    for _ = 1, 16 do
      sleep(0.5)
      local v = readNow()
      if v < minv then minv = v end
      if v > maxv then maxv = v end
    end
    motorStop()
    sleep(R.assentar)
    fim = true
  end)

  if not fim then
    print()
    print("Teste interrompido.")
    return
  end

  print()
  print("variacao da geracao durante o giro: " .. pgapi.fmt(maxv - minv, meterUnit))
  print()
  if parado > 0 and (maxv - minv) < parado * 0.02 then
    print("A geracao quase nao mudou. Provaveis causas:")
    print(" - o painel nao girou: falta torque chegando ao bearing,")
    print("   ou a embreagem esta no rele/lado errado")
    print("   (rode 'configurar' de novo)")
    print(" - a embreagem esta invertida (marque isso em 'configurar')")
    print(" - o medidor nao esta na saida deste bearing")
  else
    print("Montagem OK - girar muda a geracao, que e do que")
    print("o rastreador precisa. Rode 'suntrack'.")
  end
  return
end

if cmd == "varrer" then
  comCleanup(function()
    local peak = sweep()
    print()
    print("Pico de geracao na volta completa: " .. pgapi.fmt(peak, meterUnit))
  end)
  return
end

--- Laco principal do rastreador.
local function tracker()
  local aligned = false
  ultimaBusca = -math.huge   -- a primeira busca do dia nao espera cooldown

  while true do
    current = measure()

    -- a curva do dia aprende com o melhor de cada hora
    if pgapi.isDaytime() and current > 0 then
      clima.registrar(current)
      diaSoma, diaN = diaSoma + current, diaN + 1
      if current > diaPico then diaPico = current end
    end
    ceu = clima.avaliar(current, pgapi.isDaytime())

    -- noite: painel travado, so confere de vez em quando
    if not pgapi.isDaytime() and current < R.potenciaNoite then
      -- fecha o dia uma vez por noite: guarda o resumo e a tendencia
      if not diaFechado and diaN > 0 then
        clima.fecharDia({
          data = pgapi.gameClock(),
          pico = diaPico,
          medio = diaSoma / diaN,
          amostras = diaN,
          condicao = (ceu and ceu.condicao) or "?",
        })
        diaFechado = true
      end
      setState("noite", "painel travado ate o amanhecer")
      motorStop()
      aligned = false
      best = 0
      sleep(R.checagemNoite)

    -- bateria cheia: a corrente cai porque a tensao dela encostou na do
    -- painel, nao porque o painel saiu de posicao. Nao adianta girar.
    elseif bateriaCheia() then
      setState("bateria cheia", "nada a otimizar, painel travado")
      motorStop()
      aligned = false
      sleep(R.checagemNoite)

    -- ainda nao alinhado hoje: varredura completa para achar o maximo
    elseif not aligned then
      if diaFechado then
        diaSoma, diaN, diaPico, diaFechado = 0, 0, 0, false
      end
      local peak = sweep()
      ultimaBusca = os.clock()
      if peak < R.potenciaNoite then
        setState("sem sol", "geracao quase zero, esperando")
        motorStop()
        sleep(R.checagemNoite)
      else
        goToPeak(peak)
        aligned = true
        setState("alinhado", "")
      end

    -- alinhado: confere de tempos em tempos e corrige de leve
    else
      sleep(R.conferir)
      current = measure()

      local limite = best * (1 - R.rearmar)

      if current < limite then
        -- Caiu muito. Antes de sair girando: nuvem passa sozinha, e o sol
        -- descendo nao volta por rotacao nenhuma. So vale girar se a queda
        -- persistir E se ja tiver passado tempo desde a ultima varredura.
        local baixas = 1
        for _ = 2, R.confirmacoes do
          setState("conferindo", "geracao caiu, vendo se e passageiro")
          sleep(3)
          current = measure()
          if current < limite then baixas = baixas + 1 end
        end

        local persistiu = baixas >= R.confirmacoes
        local esperou = (os.clock() - ultimaBusca) >= R.espera
        ceu = clima.avaliar(current, pgapi.isDaytime())

        if persistiu and not clima.valeGirar(ceu) then
          -- esta chovendo: o problema esta no ceu, nao no angulo. Girar so
          -- gastaria energia atras de sol que nao existe agora.
          setState("esperando o tempo", ceu.texto .. ", nao adianta girar")
          best = best * 0.97

        elseif persistiu and esperou then
          setState("reajustando", "queda persistente, procurando de novo")
          best = current
          aligned = false
        elseif persistiu then
          -- e cedo para procurar de novo. baixa o alvo e continua parado,
          -- em vez de girar sem parar atras de energia que nao tem.
          local falta = math.ceil(R.espera - (os.clock() - ultimaBusca))
          setState("aguardando", "queda real, mas so procuro em " .. falta .. "s")
          best = best * 0.97
        else
          setState("alinhado", "foi passageiro")
        end

      else
        refine()
        -- o pico do dia decai naturalmente ao entardecer; deixa o alvo
        -- acompanhar, senao a tarde inteira parece desalinho
        best = best * 0.999
      end
    end
  end
end

local function keyLoop()
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q then return end
  end
end

comCleanup(function()
  desenhar()
  parallel.waitForAny(tracker, keyLoop)
end)

tela:encerrar()
print("suntrack encerrado. Painel travado.")]=]
ARQUIVOS["painel.lua"] = [=[
--[[ painel - o diagrama vivo do circuito solar

  Mostra o sistema inteiro desenhado, com a energia correndo pelas linhas e a
  bateria enchendo. Feito para ficar ligado num monitor grande.

  Uso:  painel        usa o monitor, se houver
        painel pc     forca a tela do computador

  Num Advanced Monitor (o dourado) da para TOCAR nos blocos: clique com o
  botao direito num deles para ver os detalhes, e de novo para fechar.
  Monitor comum nao tem toque - so o teclado funciona.

  Q sai, R re-varre os perifericos.
]]

local BASE = fs.getDir(shell.getRunningProgram())
local function lib(n)
  local p = fs.combine(BASE, n .. ".lua")
  if not fs.exists(p) then error("falta " .. n .. ".lua", 0) end
  return dofile(p)
end

local pgapi    = lib("pgapi")
local pixel    = lib("pixel")
local palette  = lib("palette")
local circuito = lib("circuito")
local rendimento = lib("rendimento")
local clima = lib("clima")
local config = lib("config")

local cfg = config.ler()
local args = { ... }
local scan = pgapi.scan()

local tela = term.current()
if args[1] ~= "pc" then
  local m = pgapi.escolherMonitor(scan, cfg.monitor)
  if m then
    tela = m.dev
    pcall(tela.setTextScale, 0.5)
  end
end

local fb = pixel.novo(tela)

local lista, tipo, unidade = pgapi.escolherMedidor(scan, cfg.medidor)

local function geracao()
  if not tipo then return 0 end
  local soma = 0
  for _, e in ipairs(lista) do
    local g = pgapi.readGauge(e, tipo)
    if g then soma = soma + math.abs(g.value) end
  end
  return soma
end

local function bateria()
  local maior
  for _, e in ipairs(scan.battery) do
    local b = pgapi.readBattery(e)
    if b and b.pct then maior = math.max(maior or 0, b.pct) end
  end
  return maior
end

-- quantos paineis existem no bearing. 0 = nao sei, e ai o painel usa so a
-- referencia empirica (o melhor ja registrado).
local PAINEIS = cfg.paineis or 0

local pico, fase = 0, 0
local sair = false
local areas          -- hitboxes devolvidas pelo circuito, em celulas
local detalhe        -- nome do bloco tocado, ou nil
local detalheAte = 0 -- ate quando mostrar

--- Cartao de detalhe por cima do diagrama, quando o bloco e tocado.
local function cartao(nome)
  local cw, ch = tela.getSize()
  local linhas = { nome:upper() }

  if nome == "medidor" then
    if not tipo then
      linhas[#linhas + 1] = "nenhum medidor na rede"
    else
      for _, e in ipairs(lista) do
        local g = pgapi.readGauge(e, tipo)
        linhas[#linhas + 1] = e.name
        if g then
          linhas[#linhas + 1] = "  " .. pgapi.fmt(math.abs(g.value), unidade)
          if g.max then
            linhas[#linhas + 1] = "  faixa ate " .. pgapi.fmt(g.max, unidade)
          end
        end
      end
    end

  elseif nome == "bateria" then
    if #scan.battery == 0 then
      linhas[#linhas + 1] = "nenhuma bateria na rede"
    else
      for _, e in ipairs(scan.battery) do
        local b = pgapi.readBattery(e)
        linhas[#linhas + 1] = e.name
        if b then
          linhas[#linhas + 1] = "  " ..
            (b.pct and string.format("%.0f%%  ", b.pct) or "") ..
            pgapi.fmt(b.energy, "J", 1)
          if b.capacity then
            linhas[#linhas + 1] = "  de " .. pgapi.fmt(b.capacity, "J", 1)
          end
          if b.draw and math.abs(b.draw) > 1e-6 then
            linhas[#linhas + 1] = "  " ..
              (b.draw >= 0 and "carregando " or "descarregando ") ..
              pgapi.fmt(math.abs(b.draw), "W")
          end
        end
      end
    end

  elseif nome == "painel" then
    local ger = geracao()
    local r = rendimento.avaliar(ger, PAINEIS, unidade)
    linhas[#linhas + 1] = "gerando " .. pgapi.fmt(ger, unidade)
    linhas[#linhas + 1] = "pico da sessao " .. pgapi.fmt(pico, unidade)
    if r.pico then
      linhas[#linhas + 1] = "melhor ja visto " .. pgapi.fmt(r.pico, unidade)
    end
    linhas[#linhas + 1] = ""
    if r.pctPico then
      linhas[#linhas + 1] = string.format("%.0f%% do melhor ja visto  (%s)",
                                          r.pctPico, r.texto)
    else
      linhas[#linhas + 1] = "ainda aprendendo o maximo desta base"
    end
    if r.pctNominal then
      linhas[#linhas + 1] = string.format("%.0f%% do nominal de catalogo",
                                          r.pctNominal)
      linhas[#linhas + 1] = "  (100% nominal nao e atingivel)"
    else
      linhas[#linhas + 1] = "rode 'configurar' e diga quantos paineis"
      linhas[#linhas + 1] = "  tem para comparar com o catalogo"
    end
    local c = clima.avaliar(ger, pgapi.isDaytime())
    linhas[#linhas + 1] = ""
    linhas[#linhas + 1] = "ceu: " .. c.texto ..
      (c.pct and string.format("  (%.0f%% do normal desta hora)", c.pct) or "")

    local t = clima.tendencia()
    if t then
      linhas[#linhas + 1] = string.format("ontem rendeu %.0f%% da media",
                                          t.pct)
    end

    local motivo = rendimento.porque(r, pgapi.isDaytime(), bateria())
    if motivo and c.condicao ~= "chuva" then
      linhas[#linhas + 1] = ""
      linhas[#linhas + 1] = "provavel causa:"
      linhas[#linhas + 1] = "  " .. motivo
    end

  else
    linhas[#linhas + 1] = "relogio do jogo " .. pgapi.gameClock()
    linhas[#linhas + 1] = ""
    linhas[#linhas + 1] = "toque num bloco para ver detalhes"
    linhas[#linhas + 1] = "Q sai, R re-varre os perifericos"
  end

  local larg = 0
  for _, l in ipairs(linhas) do larg = math.max(larg, #l) end
  larg = math.min(larg + 4, cw - 2)
  local alt = #linhas + 2
  local x = math.max(1, math.floor((cw - larg) / 2))
  local y = math.max(1, math.floor((ch - alt) / 2))

  for i = 0, alt - 1 do
    tela.setBackgroundColor(colors.gray)
    tela.setCursorPos(x, y + i)
    tela.write((" "):rep(larg))
  end
  for i, l in ipairs(linhas) do
    tela.setBackgroundColor(colors.gray)
    tela.setTextColor(i == 1 and colors.yellow or colors.white)
    tela.setCursorPos(x + 2, y + i)
    tela.write(l:sub(1, larg - 3))
  end
  tela.setBackgroundColor(colors.black)
end

local function desenhar()
  while not sair do
    local ger = geracao()
    if ger > pico then pico = ger end
    pico = pico * 0.9995   -- o pico do dia decai devagar, senao nunca cai

    -- so registra pico de dia: a noite o zero nao ensina nada
    if ger > 0.001 and pgapi.isDaytime() then
      rendimento.registrar(ger)
      clima.registrar(ger)
    end
    local rend = rendimento.avaliar(ger, PAINEIS, unidade)
    local ceu = clima.avaliar(ger, pgapi.isDaytime())

    local estado
    if not tipo then
      estado = "sem medidor"
    elseif ger <= 0.001 then
      estado = pgapi.isDaytime() and "sem geracao" or "noite"
    elseif ceu.condicao == "chuva" then
      estado = "chovendo"
    elseif rend.pctPico then
      estado = string.format("%.0f%% do melhor", rend.pctPico)
    else
      estado = "gerando"
    end

    areas = circuito.desenhar(fb, tela, {
      geracao    = ger,
      unidade    = unidade,
      pico       = pico,
      bateriaPct = bateria(),
      estado     = estado,
      girando    = ger > 0.001,
    }, fase)

    if detalhe and os.clock() < detalheAte then
      cartao(detalhe)
    else
      detalhe = nil
    end

    fase = fase + 1.2
    sleep(0.1)
  end
end

local function eventos()
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "key" then
      if a == keys.q then sair = true; return end
      if a == keys.r then
        scan = pgapi.scan()
        lista, tipo, unidade = pgapi.escolherMedidor(scan, cfg.medidor)
      end
    elseif e == "monitor_touch" then
      -- b, c = coluna e linha tocadas, em celulas
      local nome = circuito.tocou(areas, b, c)
      if nome and nome == detalhe then
        detalhe = nil            -- tocar de novo no mesmo bloco fecha
      elseif nome then
        detalhe = nome
        detalheAte = os.clock() + 8
      else
        detalhe = nil            -- tocar fora fecha
      end
    end
  end
end

-- a paleta e global: sai daqui com as cores como estavam
palette.com(tela, function()
  palette.aplicar(tela, palette.PALETAS.dia)
  parallel.waitForAny(desenhar, eventos)
end)

tela.setBackgroundColor(colors.black)
tela.setTextColor(colors.white)
tela.clear()
tela.setCursorPos(1, 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("painel encerrado.")]=]
ARQUIVOS["configurar.lua"] = [=[
--[[ configurar - assistente que escreve o helios.cfg

  Pergunta o que existe de verdade na rede (medidor, monitor, reles de
  redstone) e escreve /helios.cfg. Depois disso nenhum outro programa do
  HELIOS precisa saber onde as coisas estao - todos leem de config.lua.

  Uso:  configurar
]]

local BASE = fs.getDir(shell.getRunningProgram())
local function lib(n)
  local p = fs.combine(BASE, n .. ".lua")
  if not fs.exists(p) then error("falta " .. n .. ".lua", 0) end
  return dofile(p)
end

local pgapi  = lib("pgapi")
local ui     = lib("ui")
local config = lib("config")

local tela = ui.tela(term.current(), true)   -- direto: e um assistente de texto
local C = tela.C

local function titulo(s)
  tela.destino.setBackgroundColor(C.fundo)
  tela.destino.clear()
  tela.destino.setCursorPos(1, 1)
  tela:faixa(1, C.destaque)
  tela:texto(2, 1, s, C.fundo, C.destaque)
  tela.destino.setCursorPos(1, 3)
end

--- Menu de escolha simples, devolve o item escolhido (a tabela, nao o indice).
local function escolher(titulo_, itens)
  tela.destino.setBackgroundColor(C.fundo)
  tela.destino.clear()
  tela:faixa(1, C.destaque)
  tela:texto(2, 1, "configurar HELIOS", C.fundo, C.destaque)
  local i = tela:menu(4, itens, titulo_)
  return i and itens[i] or nil
end

--- Pergunta sim/nao. Devolve boolean.
local function perguntarSN(pergunta, padrao)
  tela.destino.setCursorPos(1, tela.h - 1)
  tela.destino.setBackgroundColor(C.fundo)
  tela.destino.setTextColor(C.texto)
  write(pergunta .. (padrao and " [S/n] " or " [s/N] "))
  local resp = (read() or ""):lower()
  if resp == "" then return padrao end
  return resp:sub(1, 1) == "s"
end

--- Pergunta um numero. Devolve o numero, ou o padrao se vazio/invalido.
local function perguntarNumero(pergunta, padrao)
  tela.destino.setCursorPos(1, tela.h - 1)
  tela.destino.setBackgroundColor(C.fundo)
  tela.destino.setTextColor(C.texto)
  write(pergunta .. " [" .. tostring(padrao) .. "] ")
  local resp = tonumber(read())
  return resp or padrao
end

-- ---------------------------------------------------------- teste de lado

--- Acende um lado de cada vez no alvo escolhido, 2s cada, para o jogador ver
-- qual redstone link/fio acende. Devolve nada - e so para observar.
local function testarLados(saidaBase)
  titulo("testando os lados")
  tela:texto(2, 3, "Olhe o bloco e anote qual lado acende.", C.fraco)
  tela:texto(2, 4, "Tecle Q para parar e escolher.", C.fraco)

  local y = 6
  for _, lado in ipairs(config.LADOS) do
    tela:texto(2, y, "lado: " .. lado, C.destaque)
    y = y + 1
    for _, l in ipairs(config.LADOS) do
      config.setBool({ rele = saidaBase.rele, lado = l }, false)
    end
    config.setBool({ rele = saidaBase.rele, lado = lado }, true)

    local parar = false
    parallel.waitForAny(
      function() sleep(2) end,
      function()
        local _, k = os.pullEvent("key")
        if k == keys.q then parar = true end
      end
    )
    if parar then break end
  end
  for _, l in ipairs(config.LADOS) do
    config.setBool({ rele = saidaBase.rele, lado = l }, false)
  end
end

--- Escolhe o rele (computador ou um redstone_relay da rede) e o lado.
-- @param permiteNenhum true para o cambio, que pode nao existir
local function escolherSaida(nomeParte, scan, permiteNenhum)
  local itens = { { rotulo = "Direto no computador", valor = config.COMPUTADOR } }
  for _, r in ipairs(scan.relay) do
    itens[#itens + 1] = { rotulo = "Redstone relay: " .. r.name, valor = r.name }
  end
  if permiteNenhum then
    itens[#itens + 1] = { rotulo = "Nenhum (sem " .. nomeParte .. ")", valor = config.NENHUM }
  end

  local escolha = escolher("Onde esta a " .. nomeParte .. "?", itens)
  if not escolha or escolha.valor == config.NENHUM then
    return { rele = config.NENHUM, lado = "top" }
  end

  local rele = escolha.valor
  if perguntarSN("Quer testar os lados agora?", true) then
    testarLados({ rele = rele })
  end

  local ladoItens = {}
  for _, l in ipairs(config.LADOS) do ladoItens[#ladoItens + 1] = { rotulo = l, valor = l } end
  local ladoEsc = escolher("Qual lado e a " .. nomeParte .. "?", ladoItens)
  local lado = ladoEsc and ladoEsc.valor or "top"

  return { rele = rele, lado = lado }
end

-- ------------------------------------------------------------------ etapas

local function passoMedidor(scan, cfg)
  local itens = { { rotulo = "Automatico (recomendado)", valor = config.AUTO } }
  for _, cat in ipairs(pgapi.MEDIDORES) do
    for _, e in ipairs(scan[cat]) do
      itens[#itens + 1] = { rotulo = e.name .. "  (" .. cat .. ")", valor = e.name }
    end
  end
  if #itens == 1 then
    tela:texto(2, tela.h - 2, "nenhum medidor visto ainda - deixando automatico", C.atencao)
    sleep(2)
  end
  local esc = escolher("Qual medidor acompanha o painel?", itens)
  cfg.medidor = esc and esc.valor or config.AUTO
end

local function passoMonitor(scan, cfg)
  local itens = {
    { rotulo = "Automatico (primeiro encontrado)", valor = config.AUTO },
    { rotulo = "Nenhum (so a tela do computador)", valor = config.NENHUM },
  }
  for _, m in ipairs(scan.monitor) do
    -- pgapi.try devolve so um valor; getSize devolve dois, entao chama direto
    local ok, w, h = pcall(m.dev.getSize)
    itens[#itens + 1] = { rotulo = m.name .. ((ok and w) and ("  " .. w .. "x" .. h) or ""),
                           valor = m.name }
  end
  local esc = escolher("Qual monitor usar?", itens)
  cfg.monitor = esc and esc.valor or config.AUTO
end

local function passoEmbreagem(scan, cfg)
  local s = escolherSaida("embreagem (Clutch)", scan, false)
  cfg.embreagem.rele = s.rele
  cfg.embreagem.lado = s.lado
  cfg.embreagem.invertida = perguntarSN("Ha uma tocha invertendo o sinal?", false)
  cfg.embreagem.analogica = perguntarSN("E um Generator Clutch (sinal analogico)?", false)
  if cfg.embreagem.analogica then
    cfg.embreagem.nivelGiro = perguntarNumero("Nivel ao girar (0=total, 15=parado)", 0)
  end
end

local function passoCambio(scan, cfg)
  local s = escolherSaida("cambio (Gearshift)", scan, true)
  cfg.cambio.rele = s.rele
  cfg.cambio.lado = s.lado
end

local function passoPaineis(cfg)
  cfg.paineis = perguntarNumero("Quantos paineis no bearing? (0 = nao sei)", cfg.paineis or 0)
end

-- ------------------------------------------------------------------ principal

local function principal()
  local scan = pgapi.scan()
  local cfg = config.ler()

  titulo("bem-vindo")
  tela:texto(2, 3, "Vou perguntar onde cada coisa esta ligada.", C.texto)
  tela:texto(2, 4, "As respostas ficam em /helios.cfg.", C.fraco)
  tela:texto(2, 6, "Perifericos vistos agora:", C.destaque)
  local y = 7
  for _, cat in ipairs({ "power", "current", "voltage", "battery", "monitor", "relay" }) do
    tela:texto(2, y, "  " .. cat .. ": " .. #scan[cat], C.fraco)
    y = y + 1
  end
  tela:texto(2, y + 1, "tecle algo para comecar", C.fraco)
  os.pullEvent("key")

  passoMedidor(scan, cfg)
  passoMonitor(scan, cfg)
  passoEmbreagem(scan, cfg)
  passoCambio(scan, cfg)
  passoPaineis(cfg)

  config.salvar(cfg)

  titulo("pronto")
  tela:texto(2, 3, "Configuracao salva em /helios.cfg", C.bom)
  tela:texto(2, 5, "medidor:   " .. tostring(cfg.medidor), C.texto)
  tela:texto(2, 6, "monitor:   " .. tostring(cfg.monitor), C.texto)
  tela:texto(2, 7, "embreagem: " .. config.descrever(cfg.embreagem), C.texto)
  tela:texto(2, 8, "cambio:    " .. config.descrever(cfg.cambio), C.texto)
  tela:texto(2, 9, "paineis:   " .. tostring(cfg.paineis), C.texto)
  tela:texto(2, 11, "Rode 'suntrack testar' para conferir a montagem.", C.fraco)
end

local ok, err = pcall(principal)
tela.destino.setBackgroundColor(colors.black)
tela.destino.setTextColor(colors.white)
if not ok then
  print()
  printError(err)
end]=]
ARQUIVOS["soldemo.lua"] = [=[
--[[ soldemo - demonstracao da base grafica nova

  Nao faz parte do sistema: serve para conferir, dentro do jogo, que os
  caracteres de subpixel e a paleta se comportam como o codigo espera.
  Se o sol sair redondo e as cores voltarem ao normal no fim, a base esta boa.

  Uso:  soldemo          usa o monitor, se houver
        soldemo pc       forca a tela do computador
]]

local BASE = fs.getDir(shell.getRunningProgram())
local function lib(n)
  local p = fs.combine(BASE, n .. ".lua")
  if not fs.exists(p) then error("falta " .. n .. ".lua", 0) end
  return dofile(p)
end

local pixel   = lib("pixel")
local palette = lib("palette")

-- escolhe a maior tela disponivel
local args = { ... }
local tela = term.current()
if args[1] ~= "pc" then
  local m = peripheral.find("monitor")
  if m then
    pcall(m.setTextScale, 0.5)
    tela = m
  end
end

local cw, ch = tela.getSize()
local fb = pixel.novo(tela)

-- estrelas fixas, para nao piscarem entre quadros
local estrelas = {}
for _ = 1, math.floor(fb.w * fb.h / 90) do
  estrelas[#estrelas + 1] = {
    math.random(1, fb.w),
    math.random(1, math.floor(fb.h * 0.6)),
  }
end

local solX = math.floor(fb.w / 2)
local raio = math.max(3, math.floor(math.min(fb.w, fb.h) / 7))
local chao = fb.h - math.floor(fb.h / 5)

--- Desenha a cena com o sol a uma dada altura.
local function cena(solY, fase)
  fb:limpar(colors.black)

  for _, e in ipairs(estrelas) do
    if e[2] < solY - raio then fb:ponto(e[1], e[2], colors.gray) end
  end

  -- raios pulsando: comprimento varia com a fase
  local comp = raio + 2 + math.floor(math.sin(fase) * 2 + 2)
  for i = 0, 7 do
    local a = (i / 8) * math.pi * 2 + fase * 0.15
    fb:linha(solX + math.cos(a) * (raio + 1),
             solY + math.sin(a) * (raio + 1),
             solX + math.cos(a) * comp,
             solY + math.sin(a) * comp,
             colors.yellow)
  end

  fb:circulo(solX, solY, raio, colors.orange, true)
  fb:circulo(solX, solY, math.max(1, raio - 2), colors.yellow, true)

  -- horizonte
  fb:linha(1, chao, fb.w, chao, colors.gray)
  fb:enviar()
end

local function escrever(y, s, cor)
  tela.setTextColor(cor or colors.white)
  tela.setBackgroundColor(colors.black)
  tela.setCursorPos(math.max(1, math.floor((cw - #s) / 2) + 1), y)
  tela.write(s)
end

-- a paleta e global: tudo daqui para baixo roda dentro de palette.com,
-- que devolve as cores no fim aconteca o que acontecer
local ok, err = palette.com(tela, function()
  local P = palette.PALETAS
  local passos = 34
  local altoY = math.floor(fb.h * 0.34)

  for i = 0, passos do
    local t = i / passos

    -- sol sobe do horizonte ate a posicao final
    local solY = math.floor(chao - (chao - altoY) * t)

    -- noite -> amanhecer na primeira metade, amanhecer -> dia na segunda
    if t < 0.5 then
      palette.tween(tela, P.noite, P.amanhecer, t * 2)
    else
      palette.tween(tela, P.amanhecer, P.dia, (t - 0.5) * 2)
    end

    cena(solY, i * 0.4)
    sleep(0.08)
  end

  escrever(math.floor(ch / 2), "H E L I O S", colors.white)
  escrever(math.floor(ch / 2) + 2,
           cw .. "x" .. ch .. " chars  ->  " .. fb.w .. "x" .. fb.h .. " pontos",
           colors.lightGray)
  escrever(ch - 1, "tecle algo para sair", colors.gray)

  os.pullEvent("key")
end)

-- limpar as duas telas: a do monitor e a do computador
tela.setBackgroundColor(colors.black)
tela.setTextColor(colors.white)
tela.clear()
tela.setCursorPos(1, 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

print("Demo encerrada. Paleta restaurada.")
print("Tela usada: " .. cw .. "x" .. ch .. " caracteres, " ..
      fb.w .. "x" .. fb.h .. " pontos.")
if not ok and err and err ~= "Terminated" then
  printError(err)
end]=]
ARQUIVOS["startup.lua"] = [=[
--[[ startup - tela de boot e menu do sistema HELIOS

     Roda sozinho quando o computador liga. Faz uma checagem de verdade do
     hardware (nao e enfeite: o que aparece aqui e o que os programas vao
     encontrar) e depois abre o menu.

     Segure qualquer tecla durante o boot para pular a animacao.
]]

local BASE = fs.getDir(shell.getRunningProgram())

local function carregar(nome)
  local p = fs.combine(BASE, nome .. ".lua")
  if not fs.exists(p) then
    error("Falta " .. nome .. ".lua - rode o instalador de novo", 0)
  end
  return dofile(p)
end

local ui      = carregar("ui")
local pgapi   = carregar("pgapi")
local pixel   = carregar("pixel")
local palette = carregar("palette")
local boot    = carregar("boot")
local config  = carregar("config")

local tela = ui.tela(term.current())
local C = tela.C

-- pular a animacao se o usuario apertar algo
local pular = false
local function vigiaTecla()
  os.pullEvent("key")
  pular = true
end

local function pausa(s)
  if pular then return end
  local fim = os.clock() + s
  while os.clock() < fim and not pular do sleep(0.05) end
end

-- ------------------------------------------------------------------- splash

--- Onde a animacao cabe melhor. No monitor ela nao atrapalha ninguem: o
-- computador segue livre para a checagem, entao ali ela roda sempre inteira.
-- Na tela do PC ela bloqueia, e ai vale poupar quem ja viu.
local function telaDoBoot()
  local scan = pgapi.scan()
  if #scan.monitor > 0 then
    local m = scan.monitor[1].dev
    pcall(m.setTextScale, 0.5)
    return m, true
  end
  return term.current(), false
end

local function splash()
  local tela, ehMonitor = telaDoBoot()
  local modo = "completo"
  if not ehMonitor and boot.jaViu() then modo = "curto" end
  boot.rodar(tela, modo, pixel, palette)
  boot.marcarVisto()
end

-- ------------------------------------------------------------------ checagem

--- Cada etapa devolve estado ("bom"/"fraco"/"ruim") e um detalhe.
local function etapas()
  local scan = pgapi.scan()

  local cfg, origemCfg = config.ler()

  local function medidor()
    local lista, cat = pgapi.escolherMedidor(scan, cfg.medidor)
    if #lista == 0 then
      if cfg.medidor ~= config.AUTO and cfg.medidor ~= "" then
        return "ruim", "\"" .. cfg.medidor .. "\" nao encontrado - rode configurar"
      end
      return "ruim", "nenhum medidor na rede"
    end
    -- tensao serve, mas mal: a Voc do painel quase nao muda com a luz
    local fraco = (cat == "voltage")
    return fraco and "atencao" or "bom",
           #lista .. "x " .. cat .. " gauge" .. (fraco and " (fraco)" or "")
  end

  local function baterias()
    if #scan.battery == 0 then return "fraco", "nenhuma" end
    local carga
    for _, b in ipairs(scan.battery) do
      local r = pgapi.readBattery(b)
      if r and r.pct then carga = math.max(carga or 0, r.pct) end
    end
    return "bom", #scan.battery .. "x  " ..
           (carga and string.format("%.0f%% de carga", carga) or "sem leitura")
  end

  local function monitor()
    if #scan.monitor == 0 then return "fraco", "nenhum, painel usa esta tela" end
    local m = pgapi.escolherMonitor(scan, cfg.monitor)
    if not m then return "atencao", cfg.monitor .. " nao encontrado - rode configurar" end
    local w, h = m.dev.getSize()
    return "bom", #scan.monitor .. "x  " .. w .. "x" .. h
  end

  local function embreagem()
    local desc = config.descrever(cfg.embreagem)
    if origemCfg == "padrao" then
      return "atencao", desc .. " (nunca configurado - rode configurar)"
    end
    if not config.saidaOk(cfg.embreagem) then
      return "atencao", desc .. " (rele nao visto agora)"
    end
    return "bom", desc
  end

  local function rede()
    local n = 0
    for _, nome in ipairs(peripheral.getNames()) do
      if peripheral.hasType(nome, "modem") then n = n + 1 end
    end
    if n == 0 then return "ruim", "nenhum - nada sera visto" end
    return "bom", n .. " modem" .. (n > 1 and "s" or "")
  end

  return {
    { "modems",    rede },
    { "medidor",   medidor },
    { "embreagem", embreagem },
    { "baterias",  baterias },
    { "monitor",   monitor },
  }, scan
end

local function checagem()
  local lista, scan = etapas()
  tela:limpar()
  tela:cabecalho("HELIOS", pgapi.gameClock())
  tela:texto(2, 3, "verificando o sistema", C.fraco)

  local resultados = {}
  for i, etapa in ipairs(lista) do
    tela:barra(2, 5, tela.w - 2, (i - 1) / #lista * 100, C.destaque)
    tela:mostrar()

    local ok, estado, detalhe = pcall(etapa[2])
    if not ok then estado, detalhe = "ruim", "erro na checagem" end
    resultados[i] = { nome = etapa[1], estado = estado, detalhe = detalhe }

    local y = 7 + (i - 1)
    tela:estado(2, y, estado, etapa[1])
    tela:texto(18, y, detalhe or "", C.fraco)
    tela:mostrar()
    pausa(0.18)
  end

  tela:barra(2, 5, tela.w - 2, 100, C.bom)
  tela:mostrar()
  pausa(0.5)
  return resultados, scan
end

-- --------------------------------------------------------------------- menu

local function rodar(programa, ...)
  tela:encerrar()
  local ok, err = pcall(shell.run, programa, ...)
  if not ok then
    print()
    printError(err)
    print()
    print("Tecle algo para voltar ao menu.")
    os.pullEvent("key")
  end
end

local function menu(resultados)
  local problemas = 0
  for _, r in ipairs(resultados) do
    if r.estado == "ruim" then problemas = problemas + 1 end
  end

  while true do
    tela:limpar()
    tela:cabecalho("HELIOS", pgapi.gameClock())

    if problemas > 0 then
      tela:texto(2, 3, problemas .. " item(ns) com problema - veja 'diagnostico'", C.ruim)
    else
      tela:texto(2, 3, "sistema pronto", C.bom)
    end

    local itens = {
      { rotulo = "Configurar a montagem", dica = "configurar" },
      { rotulo = "Painel visual",         dica = "painel" },
      { rotulo = "Painel de energia",     dica = "pgmon" },
      { rotulo = "Rastrear o sol",        dica = "suntrack" },
      { rotulo = "Testar a montagem",     dica = "suntrack testar" },
      { rotulo = "Diagnostico",           dica = "" },
      { rotulo = "Rever o amanhecer",     dica = "" },
      { rotulo = "Sair para o shell",     dica = "" },
    }

    tela:rodape(" setas move  enter escolhe  q sai ")
    local escolha = tela:menu(7, itens, "o que voce quer fazer?")

    if escolha == nil or escolha == 8 then
      tela:encerrar()
      print("HELIOS encerrado. Digite 'startup' para voltar.")
      return
    elseif escolha == 1 then
      rodar("configurar")
      resultados = checagem()
    elseif escolha == 2 then rodar("painel")
    elseif escolha == 3 then rodar("pgmon")
    elseif escolha == 4 then rodar("suntrack")
    elseif escolha == 5 then rodar("suntrack", "testar")
    elseif escolha == 7 then
      boot.rodar((telaDoBoot()), "completo", pixel, palette)
    elseif escolha == 6 then
      tela:limpar()
      tela:cabecalho("HELIOS", "diagnostico")
      for i, r in ipairs(resultados) do
        local y = 3 + (i - 1) * 2
        tela:estado(2, y, r.estado, r.nome)
        tela:texto(4, y + 1, r.detalhe or "", C.fraco)
      end
      tela:rodape(" qualquer tecla volta ")
      tela:mostrar()
      os.pullEvent("key")
    end
  end
end

-- ----------------------------------------------------------------- principal

--- Com monitor, o sol nasce la enquanto o computador faz a checagem aqui:
-- waitForAll espera as duas, entao a animacao sempre completa.
-- Sem monitor, as duas dividem a mesma tela e tem que ser em sequencia.
local function checagem_completa()
  local _, ehMonitor = telaDoBoot()
  local r
  if ehMonitor then
    parallel.waitForAll(splash, function() r = checagem() end)
  else
    splash()
    r = checagem()
  end
  return r
end

-- O vigia so vive durante a animacao. Se ele continuasse durante o menu,
-- roubaria a primeira tecla que o menu espera.
local resultados

parallel.waitForAny(
  function() resultados = checagem_completa() end,
  vigiaTecla
)

-- se o usuario pulou no meio, a checagem nao chegou a devolver nada
if not resultados then resultados = checagem() end

-- ------------------------------------------- ponte com a Expresso Labs
-- Opcional: sem ponte.lua instalado, nada aqui muda e o HELIOS roda igual.
-- A ponte SO LE os medidores e manda para o servidor da empresa. Ela vive em
-- paralelo com o menu, dentro de pcall - falha dela nunca derruba o HELIOS.
local ponte
if fs.exists(fs.combine(BASE, "ponte.lua")) then
  local ok, m = pcall(dofile, fs.combine(BASE, "ponte.lua"))
  if ok and type(m) == "table" then ponte = m end
end

if ponte then
  parallel.waitForAny(
    function() menu(resultados) end,
    function()
      pcall(ponte.rodar)
      -- se a ponte morrer, ela dorme aqui: retornar fecharia o menu junto
      while true do sleep(60) end
    end
  )
else
  menu(resultados)
end]=]

for _, nome in ipairs(ORDEM) do
  if fs.exists(nome) then fs.delete(nome) end
  local f = fs.open(nome, "w")
  f.write(ARQUIVOS[nome])
  f.close()
  print("gravado: " .. nome)
end
print()
print(#ORDEM .. " arquivos instalados.")
print("Rode 'configurar' para dizer onde estao o medidor,")
print("a embreagem e o cambio. Ctrl+R para reiniciar depois.")
