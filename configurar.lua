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
end
