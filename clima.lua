--[[ clima - aprende a curva do dia e infere a condicao do ceu

  Nenhum mod deste perfil expoe o clima ao computador: nao existe sensor de
  chuva. O unico sensor disponivel e o proprio painel.

  Entao o sistema aprende: para cada hora do dia guarda a MAIOR geracao ja
  vista naquela hora. Isso vira a curva de um dia limpo. Comparando o agora
  com a curva, da para separar tres coisas que baixam a geracao:

    sol baixo no ceu   a curva ja preve; nao e anomalia
    nublado            metade do esperado para aquela hora
    chuva              bem abaixo do esperado para aquela hora

  LIMITE HONESTO: isto nao distingue chuva de painel quebrado, obstruido ou
  fio solto. Diz "esta gerando muito abaixo do que costuma nesta hora" - a
  causa mais provavel e o tempo, mas nao e a unica.

  A curva so vale depois de alguns dias de sol. Ate la, avaliar() devolve
  "aprendendo" em vez de inventar diagnostico.
]]

local clima = {}

local CURVA = ".helios_curva"
local DIARIO = ".helios_dias"

--- Hora do jogo como inteiro de 0 a 23.
function clima.hora()
  return math.floor(os.time()) % 24
end

-- ------------------------------------------------------------------- curva

--- Le a curva do disco. Devolve tabela hora -> maior geracao vista.
function clima.curva()
  local c = {}
  if not fs.exists(CURVA) then return c end
  local f = fs.open(CURVA, "r")
  if not f then return c end
  for linha in f.readLine do
    local h, v = linha:match("^(%d+)=([%d%.eE%+%-]+)$")
    if h then c[tonumber(h)] = tonumber(v) end
  end
  f.close()
  return c
end

local function gravarCurva(c)
  local f = fs.open(CURVA, "w")
  if not f then return end
  for h = 0, 23 do
    if c[h] then f.write(h .. "=" .. tostring(c[h]) .. "\n") end
  end
  f.close()
end

--- Registra uma leitura. So sobe o maximo daquela hora, nunca desce:
-- a curva representa o melhor caso, o dia limpo.
function clima.registrar(valor, hora)
  if type(valor) ~= "number" or valor ~= valor or valor <= 0 then return end
  hora = hora or clima.hora()
  local c = clima.curva()
  if not c[hora] or valor > c[hora] then
    c[hora] = valor
    gravarCurva(c)
  end
end

--- Quantas horas do dia ja tem referencia. Abaixo de 4, nao da para julgar.
function clima.maturidade()
  local n = 0
  for _ in pairs(clima.curva()) do n = n + 1 end
  return n
end

--- Quanto se espera nesta hora, pela curva aprendida.
-- Se a hora exata nao tem registro, usa a media das vizinhas.
function clima.esperado(hora)
  hora = hora or clima.hora()
  local c = clima.curva()
  if c[hora] then return c[hora] end
  local antes, depois = c[(hora - 1) % 24], c[(hora + 1) % 24]
  if antes and depois then return (antes + depois) / 2 end
  return antes or depois
end

-- ---------------------------------------------------------------- avaliacao

--- Classifica o ceu agora.
-- Devolve { condicao =, pct =, esperado =, texto = }
-- condicao: "aprendendo" | "noite" | "limpo" | "nublado" | "chuva"
function clima.avaliar(atual, ehDia)
  local r = { esperado = clima.esperado() }

  if ehDia == false then
    r.condicao, r.texto = "noite", "noite"
    return r
  end

  if clima.maturidade() < 4 or not r.esperado or r.esperado <= 0 then
    r.condicao, r.texto = "aprendendo", "aprendendo a curva do dia"
    return r
  end

  r.pct = atual / r.esperado * 100

  if r.pct >= 70 then
    r.condicao, r.texto = "limpo", "ceu limpo"
  elseif r.pct >= 25 then
    r.condicao, r.texto = "nublado", "nublado"
  else
    r.condicao, r.texto = "chuva", "chovendo, provavelmente"
  end
  return r
end

--- Girar o painel resolve o que esta acontecendo agora?
-- Com chuva ou nublado pesado, nao: o problema esta no ceu, nao no angulo.
function clima.valeGirar(r)
  if not r then return true end
  return r.condicao ~= "chuva"
end

-- ------------------------------------------------------------ fecho do dia

--- Guarda o resumo de um dia. Mantem os ultimos 14.
function clima.fecharDia(resumo)
  local dias = clima.dias()
  table.insert(dias, resumo)
  while #dias > 14 do table.remove(dias, 1) end

  local f = fs.open(DIARIO, "w")
  if not f then return end
  for _, d in ipairs(dias) do
    f.write(string.format("%s;%.4f;%.4f;%d;%s\n",
            d.data or "?", d.pico or 0, d.medio or 0,
            d.amostras or 0, d.condicao or "?"))
  end
  f.close()
end

--- Le os dias guardados, do mais antigo ao mais novo.
function clima.dias()
  local dias = {}
  if not fs.exists(DIARIO) then return dias end
  local f = fs.open(DIARIO, "r")
  if not f then return dias end
  for linha in f.readLine do
    local data, pico, medio, n, cond = linha:match("^([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")
    if data then
      dias[#dias + 1] = {
        data = data, pico = tonumber(pico) or 0,
        medio = tonumber(medio) or 0,
        amostras = tonumber(n) or 0, condicao = cond,
      }
    end
  end
  f.close()
  return dias
end

--- Compara o ultimo dia fechado com a media dos anteriores.
-- Devolve nil se nao houver dias suficientes para comparar.
function clima.tendencia()
  local dias = clima.dias()
  if #dias < 2 then return nil end
  local ultimo = dias[#dias]
  local soma, n = 0, 0
  for i = 1, #dias - 1 do
    soma = soma + dias[i].medio
    n = n + 1
  end
  if n == 0 or soma == 0 then return nil end
  local media = soma / n
  return {
    ultimo = ultimo,
    media = media,
    pct = ultimo.medio / media * 100,
  }
end

function clima.esquecer()
  if fs.exists(CURVA) then fs.delete(CURVA) end
  if fs.exists(DIARIO) then fs.delete(DIARIO) end
end

return clima
