--[[ diagnostico_medidor - descobre o que cada medidor de verdade devolve

  Nao depende do pgapi: chama os perifericos direto, com pcall em cada
  metodo, e grava tudo em /diagnostico_medidor.txt. Roda uma vez e me manda
  o arquivo (ou so avisa que rodou - eu leio o save direto).

  Uso: diagnostico_medidor
]]

local linhas = {}
local function log(s)
  s = tostring(s)
  print(s)
  linhas[#linhas + 1] = s
end

--- Chama um metodo com pcall e devolve uma string pronta pra imprimir.
local function chamar(dev, metodo)
  if type(dev[metodo]) ~= "function" then
    return "(nao existe)"
  end
  local ok, a, b, c = pcall(dev[metodo])
  if not ok then
    return "ERRO: " .. tostring(a)
  end
  local partes = {}
  for _, v in ipairs({ a, b, c }) do
    if v ~= nil then partes[#partes + 1] = tostring(v) end
  end
  if #partes == 0 then return "(sem valor)" end
  return table.concat(partes, ", ")
end

-- tipos de medidor que o HELIOS reconhece hoje, antigos e novos
local TIPOS = {
  "powergrid_power_gauge", "powergrid_current_gauge", "powergrid_voltage_gauge",
  "ammeter", "voltmeter", "powermeter",
}

local GETTERS = { "current", "voltage", "power", "getValue",
                   "rangePercentage", "maxRange", "getType" }

log("=== diagnostico de medidores ===")
log("hora do jogo: " .. os.time())
log("")

local achou = 0
for _, nome in ipairs(peripheral.getNames()) do
  local tipoAchado
  for _, t in ipairs(TIPOS) do
    if peripheral.hasType(nome, t) then tipoAchado = t; break end
  end
  if tipoAchado then
    achou = achou + 1
    local dev = peripheral.wrap(nome)
    log("--- " .. nome .. "  (tipo: " .. tipoAchado .. ")")

    -- lista todos os metodos que o periferico expoe de verdade
    local ok, metodos = pcall(peripheral.getMethods, nome)
    if ok and metodos then
      table.sort(metodos)
      log("  metodos: " .. table.concat(metodos, ", "))
    end

    for _, g in ipairs(GETTERS) do
      log(string.format("  %-18s -> %s", g .. "()", chamar(dev, g)))
    end
    log("")
  end
end

if achou == 0 then
  log("Nenhum medidor (dos tipos conhecidos) encontrado na rede.")
  log("Perifericos vistos:")
  for _, nome in ipairs(peripheral.getNames()) do
    log("  " .. nome .. "  (" .. peripheral.getType(nome) .. ")")
  end
end

local f = fs.open("/diagnostico_medidor.txt", "w")
f.write(table.concat(linhas, "\n"))
f.close()

print()
print("Gravado em /diagnostico_medidor.txt")
