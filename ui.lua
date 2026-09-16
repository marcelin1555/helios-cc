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

return ui
