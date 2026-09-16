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
end
