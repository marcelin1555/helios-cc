--[[ soldemo - demonstracao da base grafica nova

  Nao faz parte do sistema: serve para conferir, dentro do jogo, que os
  caracteres de subpixel e a paleta se comportam como o codigo espera.
  Se o sol sair redondo e as cores voltarem ao normal no fim, a base esta boa.

  Uso:  soldemo          usa o monitor, se houver
        soldemo pc       forca a tela do computador
]]

local BASE = fs.getDir(shell.getRunningProgram())
local function lib(n)
  local p = fs.combine(BASE, n .. ".lua")
  if not fs.exists(p) then error("falta " .. n .. ".lua", 0) end
  return dofile(p)
end

local pixel   = lib("pixel")
local palette = lib("palette")

-- escolhe a maior tela disponivel
local args = { ... }
local tela = term.current()
if args[1] ~= "pc" then
  local m = peripheral.find("monitor")
  if m then
    pcall(m.setTextScale, 0.5)
    tela = m
  end
end

local cw, ch = tela.getSize()
local fb = pixel.novo(tela)

-- estrelas fixas, para nao piscarem entre quadros
local estrelas = {}
for _ = 1, math.floor(fb.w * fb.h / 90) do
  estrelas[#estrelas + 1] = {
    math.random(1, fb.w),
    math.random(1, math.floor(fb.h * 0.6)),
  }
end

local solX = math.floor(fb.w / 2)
local raio = math.max(3, math.floor(math.min(fb.w, fb.h) / 7))
local chao = fb.h - math.floor(fb.h / 5)

--- Desenha a cena com o sol a uma dada altura.
local function cena(solY, fase)
  fb:limpar(colors.black)

  for _, e in ipairs(estrelas) do
    if e[2] < solY - raio then fb:ponto(e[1], e[2], colors.gray) end
  end

  -- raios pulsando: comprimento varia com a fase
  local comp = raio + 2 + math.floor(math.sin(fase) * 2 + 2)
  for i = 0, 7 do
    local a = (i / 8) * math.pi * 2 + fase * 0.15
    fb:linha(solX + math.cos(a) * (raio + 1),
             solY + math.sin(a) * (raio + 1),
             solX + math.cos(a) * comp,
             solY + math.sin(a) * comp,
             colors.yellow)
  end

  fb:circulo(solX, solY, raio, colors.orange, true)
  fb:circulo(solX, solY, math.max(1, raio - 2), colors.yellow, true)

  -- horizonte
  fb:linha(1, chao, fb.w, chao, colors.gray)
  fb:enviar()
end

local function escrever(y, s, cor)
  tela.setTextColor(cor or colors.white)
  tela.setBackgroundColor(colors.black)
  tela.setCursorPos(math.max(1, math.floor((cw - #s) / 2) + 1), y)
  tela.write(s)
end

-- a paleta e global: tudo daqui para baixo roda dentro de palette.com,
-- que devolve as cores no fim aconteca o que acontecer
local ok, err = palette.com(tela, function()
  local P = palette.PALETAS
  local passos = 34
  local altoY = math.floor(fb.h * 0.34)

  for i = 0, passos do
    local t = i / passos

    -- sol sobe do horizonte ate a posicao final
    local solY = math.floor(chao - (chao - altoY) * t)

    -- noite -> amanhecer na primeira metade, amanhecer -> dia na segunda
    if t < 0.5 then
      palette.tween(tela, P.noite, P.amanhecer, t * 2)
    else
      palette.tween(tela, P.amanhecer, P.dia, (t - 0.5) * 2)
    end

    cena(solY, i * 0.4)
    sleep(0.08)
  end

  escrever(math.floor(ch / 2), "H E L I O S", colors.white)
  escrever(math.floor(ch / 2) + 2,
           cw .. "x" .. ch .. " chars  ->  " .. fb.w .. "x" .. fb.h .. " pontos",
           colors.lightGray)
  escrever(ch - 1, "tecle algo para sair", colors.gray)

  os.pullEvent("key")
end)

-- limpar as duas telas: a do monitor e a do computador
tela.setBackgroundColor(colors.black)
tela.setTextColor(colors.white)
tela.clear()
tela.setCursorPos(1, 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

print("Demo encerrada. Paleta restaurada.")
print("Tela usada: " .. cw .. "x" .. ch .. " caracteres, " ..
      fb.w .. "x" .. fb.h .. " pontos.")
if not ok and err and err ~= "Terminated" then
  printError(err)
end
