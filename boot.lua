--[[ boot - a animacao do amanhecer do HELIOS

  O sol nao e redesenhado a cada quadro para fazer o fade: ele e desenhado e a
  PALETA muda. Sao 10 chamadas por quadro em vez de repintar a tela inteira.

  boot.rodar(tela, modo)   modo = "completo" (~5s) ou "curto" (~1,5s)
  boot.jaViu()             ja mostrou a versao completa neste computador?
  boot.marcarVisto()

  Qualquer tecla pula. Quem chama e responsavel por nao deixar um vigia de
  tecla vivo depois disso - senao ele rouba a primeira tecla do menu.
]]

local boot = {}

local ARQUIVO = ".helios_boot"

function boot.jaViu()
  return fs.exists(ARQUIVO)
end

function boot.marcarVisto()
  if fs.exists(ARQUIVO) then return end
  local f = fs.open(ARQUIVO, "w")
  if f then f.write("visto"); f.close() end
end

--- Esquece que ja viu, para poder rever a animacao completa.
function boot.esquecer()
  if fs.exists(ARQUIVO) then fs.delete(ARQUIVO) end
end

--- Roda a animacao. Devolve true se foi ate o fim, false se pularam.
-- A paleta e restaurada aqui dentro, em qualquer caminho de saida.
function boot.rodar(tela, modo, pixel, palette)
  local fb = pixel.novo(tela)
  local cw, ch = tela.getSize()
  local P = palette.PALETAS

  local curto  = (modo == "curto")
  local passos = curto and 12 or 34
  local espera = curto and 0.05 or 0.08

  local solX = math.floor(fb.w / 2)
  local raio = math.max(3, math.floor(math.min(fb.w, fb.h) / 7))
  local chao = fb.h - math.floor(fb.h / 5)
  local altoY = math.floor(fb.h * 0.34)

  -- estrelas fixas: sorteadas uma vez, para nao piscarem entre quadros
  local estrelas = {}
  for _ = 1, math.floor(fb.w * fb.h / 110) do
    estrelas[#estrelas + 1] = {
      math.random(1, fb.w),
      math.random(1, math.floor(fb.h * 0.55)),
    }
  end

  local pulou = false

  local function cena(solY, fase)
    fb:limpar(colors.black)

    for _, e in ipairs(estrelas) do
      if e[2] < solY - raio - 2 then fb:ponto(e[1], e[2], colors.gray) end
    end

    -- raios: dois tracos por direcao, para terem corpo
    local comp = raio + 3 + math.floor(math.sin(fase) * 2 + 2)
    for i = 0, 11 do
      local a = (i / 12) * math.pi * 2 + fase * 0.12
      local ca, sa = math.cos(a), math.sin(a)
      fb:linha(solX + ca * (raio + 2), solY + sa * (raio + 2),
               solX + ca * comp,       solY + sa * comp, colors.yellow)
      fb:linha(solX + ca * (raio + 2) + 1, solY + sa * (raio + 2),
               solX + ca * comp + 1,       solY + sa * comp, colors.orange)
    end

    fb:circulo(solX, solY, raio, colors.orange, true)
    fb:circulo(solX, solY, math.max(1, raio - 2), colors.yellow, true)

    fb:linha(1, chao, fb.w, chao, colors.gray)
    fb:enviar()
  end

  local function texto(y, s, cor)
    if y < 1 or y > ch then return end
    tela.setTextColor(cor or colors.white)
    tela.setBackgroundColor(colors.black)
    tela.setCursorPos(math.max(1, math.floor((cw - #s) / 2) + 1), y)
    tela.write(s)
  end

  local function animar()
    for i = 0, passos do
      local t = i / passos
      local solY = math.floor(chao - (chao - altoY) * t)

      if t < 0.5 then
        palette.tween(tela, P.noite, P.amanhecer, t * 2)
      else
        palette.tween(tela, P.amanhecer, P.dia, (t - 0.5) * 2)
      end

      cena(solY, i * 0.4)
      sleep(espera)
    end

    texto(math.floor(ch / 2),     "H E L I O S", colors.white)
    texto(math.floor(ch / 2) + 2, "controle solar e energia", colors.lightGray)
    sleep(curto and 0.3 or 0.9)
  end

  local function vigia()
    os.pullEvent("key")
    pulou = true
  end

  -- a paleta e global: sai daqui com as cores como estavam, sempre
  palette.com(tela, function()
    parallel.waitForAny(animar, vigia)
  end)

  return not pulou
end

return boot
