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
print("suntrack encerrado. Painel travado.")
