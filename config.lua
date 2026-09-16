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

return config
