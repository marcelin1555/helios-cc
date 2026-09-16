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

return pixel
