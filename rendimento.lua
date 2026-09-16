--[[ rendimento - quanto do possivel o sistema esta tirando

  "100%" nominal nao existe na pratica. Os numeros de catalogo do painel valem
  em STC (1000 W/m2 perpendicular, celula a 25 graus). No jogo o sol anda pelo
  ceu, a celula esquenta (NOCT 45), e parte da luz e difusa (12%) e de albedo
  (8%). Mesmo perfeitamente alinhado o painel fica abaixo do nominal.

  Por isso aqui ha DUAS referencias:

    empirica  o melhor que este sistema ja produziu, guardado em disco.
              E a referencia honesta: diz se voce esta tirando hoje o que
              ja tirou antes. Comeca a valer depois de alguns dias de sol.

    nominal   paineis x potencia de catalogo. So aparece se voce disser
              quantos paineis tem. Serve para saber a ordem de grandeza,
              nunca para esperar 100%.

  Os valores de catalogo abaixo sao os do powergrid-server.toml deste perfil.
  Se voce mexer na config do mod, ajuste aqui tambem.
]]

local rendimento = {}

local ARQUIVO = ".helios_pico"

-- catalogo do painel, de powergrid-server.toml
rendimento.PAINEL = {
  voc = 26.4,     -- tensao de circuito aberto
  isc = 3.3,      -- corrente de curto
  vmp = 21.12,    -- tensao no ponto de maxima potencia
  imp = 3.036,    -- corrente no ponto de maxima potencia
}

--- Potencia de catalogo de um painel, em W (STC).
function rendimento.porPainel()
  return rendimento.PAINEL.vmp * rendimento.PAINEL.imp
end

--- Maximo nominal para N paineis, na grandeza pedida.
-- unidade = "W" (potencia) ou "A" (corrente). nil se nao souber quantos.
function rendimento.nominal(paineis, unidade)
  paineis = tonumber(paineis) or 0
  if paineis <= 0 then return nil end
  if unidade == "A" then
    -- em serie a corrente nao soma; em paralelo soma. Assumimos paralelo,
    -- que e o caso do multibloco de paineis do mod.
    return paineis * rendimento.PAINEL.imp
  end
  return paineis * rendimento.porPainel()
end

-- ------------------------------------------------------------------ historico

--- Le o pico ja registrado. Devolve nil se nunca houve.
function rendimento.picoSalvo()
  if not fs.exists(ARQUIVO) then return nil end
  local f = fs.open(ARQUIVO, "r")
  if not f then return nil end
  local linha = f.readLine()
  f.close()
  return tonumber(linha)
end

--- Guarda um pico novo, se for maior que o anterior. Devolve o pico valendo.
function rendimento.registrar(valor)
  if type(valor) ~= "number" or valor ~= valor then return rendimento.picoSalvo() end
  local antigo = rendimento.picoSalvo()
  if antigo and valor <= antigo then return antigo end
  local f = fs.open(ARQUIVO, "w")
  if f then f.write(tostring(valor)); f.close() end
  return valor
end

function rendimento.esquecer()
  if fs.exists(ARQUIVO) then fs.delete(ARQUIVO) end
end

-- ---------------------------------------------------------------- avaliacao

--- Como esta indo agora.
-- Devolve { pctPico =, pctNominal =, pico =, nominal =, texto = }
-- pctPico e nil enquanto nao houver historico suficiente.
function rendimento.avaliar(atual, paineis, unidade)
  local r = {}
  r.pico = rendimento.picoSalvo()
  r.nominal = rendimento.nominal(paineis, unidade)

  if r.pico and r.pico > 0 then
    r.pctPico = atual / r.pico * 100
  end
  if r.nominal and r.nominal > 0 then
    r.pctNominal = atual / r.nominal * 100
  end

  if not r.pctPico then
    r.texto = "aprendendo o maximo"
  elseif r.pctPico >= 97 then
    r.texto = "no melhor ja visto"
  elseif r.pctPico >= 85 then
    r.texto = "perto do melhor"
  elseif r.pctPico >= 45 then
    -- meia geracao de manha ou no fim da tarde e o normal do dia, nao
    -- sinal de problema: o limiar do alarme fica mais embaixo
    r.texto = "abaixo do melhor"
  else
    r.texto = "bem abaixo"
  end

  return r
end

--- Motivos plausiveis para estar abaixo do pico, do mais provavel ao menos.
-- Nao adivinha: usa a hora do jogo e a carga da bateria, que sao coisas que
-- derrubam a geracao sem o painel ter saido do lugar.
function rendimento.porque(r, ehDia, bateriaPct)
  if not r.pctPico or r.pctPico >= 85 then return nil end
  if not ehDia then return "e noite" end
  if bateriaPct and bateriaPct >= 95 then
    return "bateria cheia: a tensao dela subiu e a corrente caiu"
  end
  local h = os.time()
  if h < 8 or h > 16 then
    return "sol baixo no ceu: o maximo do dia e perto do meio-dia"
  end
  if bateriaPct and bateriaPct >= 80 then
    return "bateria quase cheia, a corrente cai naturalmente"
  end
  return "pode ser nuvem, chuva, ou o painel desalinhado"
end

return rendimento
