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

return circuito
