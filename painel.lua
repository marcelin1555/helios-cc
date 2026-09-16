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

local args = { ... }
local scan = pgapi.scan()

local tela = term.current()
if args[1] ~= "pc" and #scan.monitor > 0 then
  tela = scan.monitor[1].dev
  pcall(tela.setTextScale, 0.5)
end

local fb = pixel.novo(tela)

--- Escolhe a melhor grandeza disponivel para representar a geracao.
local function medidor()
  if #scan.power > 0 then return scan.power, "power", "W" end
  if #scan.current > 0 then return scan.current, "current", "A" end
  if #scan.voltage > 0 then return scan.voltage, "voltage", "V" end
  return {}, nil, ""
end

local lista, tipo, unidade = medidor()

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
local PAINEIS = 0
if fs.exists("painel.cfg") then
  local f = fs.open("painel.cfg", "r")
  for linha in f.readLine do
    local n = linha:match("^%s*paineis%s*=%s*(%d+)%s*$")
    if n then PAINEIS = tonumber(n) end
  end
  f.close()
end

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
      linhas[#linhas + 1] = "ponha paineis=N em painel.cfg para"
      linhas[#linhas + 1] = "  comparar com o catalogo"
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
      if a == keys.r then scan = pgapi.scan(); lista, tipo, unidade = medidor() end
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
print("painel encerrado.")
