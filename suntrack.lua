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

    O computador tem saida de redstone nativa, entao esses dois blocos
    nao precisam de modem nem de periferico. So o medidor precisa.

  COMO ACHA A MELHOR POSICAO
    O bearing nao e um periferico - nao da para ler o angulo do painel.
    Entao o programa usa a propria geracao como realimentacao: gira um
    pouco, mede, e se piorou inverte o sentido. E o mesmo metodo
    "perturb & observe" dos rastreadores solares de verdade.

  MONTAGEM
    1. Uma fonte de rotacao do Create (motor, moinho, o que preferir).
       Use RPM BAIXO - 8 a 16. Em RPM alto o menor pulso ja passa do ponto.
    2. Gearshift no eixo (opcional, mas recomendado) - inverte o sentido.
    3. Clutch no eixo, depois do gearshift - liga e desliga a rotacao.
    4. O eixo entra no Solar Panel Bearing, que gira os paineis.
    5. Um medidor no circuito eletrico do bearing, ligado ao computador
       com Wired Modem + Networking Cable. Prefira o CURRENT GAUGE: ele
       tem 2 terminais e vai em serie, enquanto o Power Gauge tem 3
       (shunt em serie + referencia de tensao). Para rastrear o sol a
       corrente serve tao bem quanto a potencia - num painel solar ela
       acompanha a irradiancia quase proporcionalmente.

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
    6. O computador precisa alcancar o clutch e o gearshift com redstone
       (encostado, ou por fio de redstone saindo do lado configurado).

  ATENCAO AO ESTADO SEGURO
    O Clutch do Create para quando RECEBE redstone. Entao, com o
    computador desligado, o padrao e o painel girar sem parar. Se isso
    incomodar, ponha uma tocha de redstone invertendo o sinal entre o
    computador e o clutch, e ponha invertClutch=1 no suntrack.cfg -
    ai "computador desligado" passa a significar "painel travado".

  USO
    suntrack lados       descobre em que lado esta cada redstone link
    suntrack testar      confere a montagem - rode este primeiro
    suntrack             roda o rastreador
    suntrack varrer      da uma volta medindo e mostra o pico
    suntrack parar       trava o painel e sai
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

local pgapi = loadLib("pgapi")
local uilib = loadLib("ui")
local clima = loadLib("clima")

-- ------------------------------------------------------------------ ajustes

local CONF = {
  clutchSide   = "back",  -- lado do computador que vai ate a embreagem
  gearSide     = "",      -- lado que vai ate o cambio ("" = sem cambio)
  invertClutch = 0,       -- 1 se houver uma tocha invertendo o sinal
  clutchAnalog = 0,       -- 1 para sinal analogico (Generator Clutch)
  runLevel     = 0,       -- nivel ao girar; so com clutchAnalog=1.
                          -- 0 = torque total. 8 = metade, gira mais devagar.
  pulse        = 0.30,    -- segundos girando em cada passo fino
  settle       = 0.60,    -- espera depois do passo, para a leitura assentar
  samples      = 3,       -- leituras promediadas por medicao
  sampleGap    = 0.15,    -- intervalo entre leituras
  holdCheck    = 8,       -- segundos entre conferidas quando esta alinhado
  deadband     = 0.02,    -- 2% - queda menor que isso e ruido, nao desalinho
  reacquire    = 0.35,    -- so procura de novo se cair 35% abaixo do pico.
                          -- 12% disparava a toa: de manha e de tarde a queda
                          -- e do sol no ceu, e girar nao traz de volta.
  confirma     = 3,       -- leituras baixas seguidas antes de acreditar
  cooldown     = 90,      -- segundos minimos entre duas varreduras completas
  sweepTime    = 24,      -- segundos de uma volta completa do bearing
  nightPower   = 0.5,     -- watts abaixo disso conta como sem sol
  nightCheck   = 20,      -- segundos entre conferidas durante a noite
  battFull     = 95,      -- % de carga que conta como bateria cheia
  battResume   = 88,      -- % em que volta a rastrear
  cfgFile      = "suntrack.cfg",
}

-- suntrack.cfg pode sobrescrever qualquer ajuste acima, ex:  pulse=0.5
if fs.exists(CONF.cfgFile) then
  local f = fs.open(CONF.cfgFile, "r")
  for line in f.readLine do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*([%w%.%-]+)%s*$")
    if k and CONF[k] ~= nil then CONF[k] = tonumber(v) or v end
  end
  f.close()
end

local temCambio = CONF.gearSide ~= nil and CONF.gearSide ~= ""

-- ------------------------------------------------------------------ hardware

local scan = pgapi.scan()

-- Ordem de preferencia do medidor. Potencia e corrente acompanham a
-- irradiancia; tensao quase nao muda com a luz (a Voc de um painel varia
-- de forma logaritmica), entao so serve se a carga for um resistor fixo,
-- onde V = I*R. Com bateria a tensao fica presa e o rastreador cega.
local meterList, meterKind = scan.power, "power"
if #meterList == 0 then
  meterList, meterKind = scan.current, "current"
end
if #meterList == 0 then
  meterList, meterKind = scan.voltage, "voltage"
end
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
  abortar("Nao achei medidor nenhum (power, current ou voltage gauge).\n" ..
          "Preciso de um no circuito do bearing para saber se melhorou.\n" ..
          "Ligue um com Wired Modem + cabo, e clique no modem para ativar.")
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
  local limite = cheiaAgora and (tonumber(CONF.battResume) or 88)
                            or (tonumber(CONF.battFull) or 95)
  cheiaAgora = carga >= limite
  return cheiaAgora
end

--- Media de varias leituras, para nao decidir em cima de ruido.
local function measure()
  local sum = 0
  for i = 1, CONF.samples do
    sum = sum + readNow()
    if i < CONF.samples then sleep(CONF.sampleGap) end
  end
  return sum / CONF.samples
end

-- ------------------------------------------------------------------- motor

--- Embreagem: sinal de redstone TRAVA, ausencia de sinal libera - vale tanto
-- para o Clutch do Create quanto para o Generator Clutch do PowerGrid.
-- O Generator Clutch ainda entende nivel analogico: sinal cheio nao passa
-- rotacao nenhuma, sinal parcial limita o torque. Com clutchAnalog=1 da para
-- girar mais devagar sem precisar baixar o RPM da fonte.
-- invertClutch=1 e para quem pos uma tocha invertendo o sinal no caminho.
local function setClutch(girando)
  local nivel = 15
  if girando then nivel = math.max(0, math.min(15, tonumber(CONF.runLevel) or 0)) end
  if tonumber(CONF.invertClutch) == 1 then nivel = 15 - nivel end
  if tonumber(CONF.clutchAnalog) == 1 then
    pcall(redstone.setAnalogOutput, CONF.clutchSide, nivel)
  else
    pcall(redstone.setOutput, CONF.clutchSide, nivel > 0)
  end
end

--- O Gearshift inverte o sentido quando recebe redstone.
local function setSentido(dir)
  if not temCambio then return end
  pcall(redstone.setOutput, CONF.gearSide, dir < 0)
end

local function motorStop()
  setClutch(false)
end

local function motorStart(dir)
  setSentido(dir)
  setClutch(true)
end

--- Um passo de rotacao: solta, espera, trava, deixa assentar.
local function step(dir, dur)
  motorStart(dir)
  sleep(dur or CONF.pulse)
  motorStop()
  sleep(CONF.settle)
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

local function unidade()
  return ({ power = "W", current = "A", voltage = "V" })[meterKind] or ""
end

local function corDaFracao(f)
  if f >= 0.9 then return UC.bom end
  if f >= 0.7 then return UC.atencao end
  return UC.ruim
end

local function desenhar()
  local u = unidade()
  tela:limpar()
  tela:cabecalho("suntrack", pgapi.gameClock() ..
                 (pgapi.isDaytime() and " dia" or " noite"))

  tela:texto(2, 3, "estado", UC.fraco)
  tela:texto(11, 3, state, UC.destaque)
  if detail ~= "" then tela:texto(11, 4, detail, UC.fraco) end

  -- geracao atual, com barra relativa ao melhor do dia
  local frac = (best > 0) and (current / best) or 0
  tela:linha(6, "agora", pgapi.fmt(current, u), UC.acento)
  tela:barra(2, 7, tela.w - 2, frac * 100, corDaFracao(frac))
  tela:linha(8, "melhor hoje", pgapi.fmt(best, u))

  tela:linha(10, "sentido", (dir > 0 and "->" or "<-") ..
             (temCambio and "" or "  (so um)"))
  tela:linha(11, "embreagem", CONF.clutchSide ..
             (tonumber(CONF.clutchAnalog) == 1 and "  analog" or ""))
  tela:linha(12, "cambio", temCambio and CONF.gearSide or "nenhum")

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
               carga >= (tonumber(CONF.battFull) or 95) and UC.atencao or UC.bom)
  end

  if medidorFraco then
    tela:texto(2, 15, "! tensao quase nao muda com a luz", UC.atencao)
    tela:texto(2, 16, "  so serve com carga resistiva fixa", UC.fraco)
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
  while os.clock() - t0 < CONF.sweepTime do
    current = readNow()
    if current > peak then peak = current end
    best = peak
    desenhar()
    sleep(0.2)
  end
  motorStop()
  sleep(CONF.settle)
  return peak
end

--- Continua girando ate a geracao chegar perto do pico conhecido.
local function goToPeak(peak, tol)
  tol = tol or 0.95
  setState("posicionando", string.format("indo para %.0f%% do pico", tol * 100))
  local limit = os.clock() + CONF.sweepTime * 1.5
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

  if after < before * (1 - CONF.deadband) then
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
  term.clear()
  term.setCursorPos(1, 1)
  print("=== descobrindo os lados ===")
  print()
  print("Vou ligar um lado de cada vez, 3s em cada um.")
  print("Olhe os redstone links e anote qual acende")
  print("em qual lado.")
  print()

  local lados = { "top", "bottom", "front", "back", "left", "right" }
  local ok = pcall(function()
    for _, lado in ipairs(lados) do
      for _, l in ipairs(lados) do pcall(redstone.setOutput, l, false) end
      pcall(redstone.setOutput, lado, true)
      print("  ligado: " .. lado)
      sleep(3)
    end
  end)
  for _, l in ipairs(lados) do pcall(redstone.setOutput, l, false) end

  print()
  if not ok then
    print("Interrompido. Todos os lados desligados.")
    return
  end
  print("Todos desligados. Agora escreva no suntrack.cfg:")
  print()
  print("  clutchSide=<lado do link da embreagem>")
  print("  gearSide=<lado do link do cambio>")
  print()
  print("Use 'edit suntrack.cfg' para criar o arquivo.")
  return
end

if cmd == "parar" then
  motorStop()
  print("Painel travado (embreagem acionada no lado " .. CONF.clutchSide .. ").")
  return
end

if cmd == "testar" then
  local unit = ({ power = "W", current = "A", voltage = "V" })[meterKind] or ""
  term.clear()
  term.setCursorPos(1, 1)
  print("=== teste de montagem ===")
  print()
  print("embreagem no lado: " .. CONF.clutchSide)
  print("cambio:            " .. (temCambio and CONF.gearSide or "nenhum"))
  for _, e in ipairs(meterList) do print("medidor:           " .. e.name) end
  print()

  motorStop()
  sleep(1)
  local parado = measure()
  print("travado, gerando " .. pgapi.fmt(parado, unit))
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
    sleep(CONF.settle)
    fim = true
  end)

  if not fim then
    print()
    print("Teste interrompido.")
    return
  end

  print()
  print("variacao da geracao durante o giro: " .. pgapi.fmt(maxv - minv, unit))
  print()
  if parado > 0 and (maxv - minv) < parado * 0.02 then
    print("A geracao quase nao mudou. Provaveis causas:")
    print(" - o painel nao girou: falta torque chegando ao")
    print("   bearing, ou a embreagem esta no lado errado")
    print("   (ajuste clutchSide no suntrack.cfg)")
    print(" - a embreagem esta invertida (invertClutch=1)")
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
    print("Pico de geracao na volta completa: " ..
          pgapi.fmt(peak, ({ power = "W", current = "A", voltage = "V" })[meterKind] or ""))
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
    if not pgapi.isDaytime() and current < CONF.nightPower then
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
      sleep(CONF.nightCheck)

    -- bateria cheia: a corrente cai porque a tensao dela encostou na do
    -- painel, nao porque o painel saiu de posicao. Nao adianta girar.
    elseif bateriaCheia() then
      setState("bateria cheia", "nada a otimizar, painel travado")
      motorStop()
      aligned = false
      sleep(CONF.nightCheck)

    -- ainda nao alinhado hoje: varredura completa para achar o maximo
    elseif not aligned then
      if diaFechado then
        diaSoma, diaN, diaPico, diaFechado = 0, 0, 0, false
      end
      local peak = sweep()
      ultimaBusca = os.clock()
      if peak < CONF.nightPower then
        setState("sem sol", "geracao quase zero, esperando")
        motorStop()
        sleep(CONF.nightCheck)
      else
        goToPeak(peak)
        aligned = true
        setState("alinhado", "")
      end

    -- alinhado: confere de tempos em tempos e corrige de leve
    else
      sleep(CONF.holdCheck)
      current = measure()

      local limite = best * (1 - CONF.reacquire)

      if current < limite then
        -- Caiu muito. Antes de sair girando: nuvem passa sozinha, e o sol
        -- descendo nao volta por rotacao nenhuma. So vale girar se a queda
        -- persistir E se ja tiver passado tempo desde a ultima varredura.
        local baixas = 1
        for _ = 2, (tonumber(CONF.confirma) or 3) do
          setState("conferindo", "geracao caiu, vendo se e passageiro")
          sleep(3)
          current = measure()
          if current < limite then baixas = baixas + 1 end
        end

        local persistiu = baixas >= (tonumber(CONF.confirma) or 3)
        local esperou = (os.clock() - ultimaBusca) >= (tonumber(CONF.cooldown) or 90)
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
          local falta = math.ceil((tonumber(CONF.cooldown) or 90)
                                  - (os.clock() - ultimaBusca))
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
