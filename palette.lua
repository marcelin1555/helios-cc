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

return palette
