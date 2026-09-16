# Painel PowerGrid + rastreador solar (CC:Tweaked)

Programas para o perfil *servidor de expresso* (CC:Tweaked 1.120.2 + PowerGrid 0.6.1).

| arquivo | o que é |
|---|---|
| `startup.lua` | boot do sistema HELIOS: checagem de hardware + menu |
| `pgapi.lua` | biblioteca: descobre e lê os periféricos do PowerGrid |
| `ui.lua` | biblioteca de interface: telas, barras, menus |
| `pgmon.lua` | painel de monitoramento num monitor |
| `suntrack.lua` | rastreador solar automático |
| `pixel.lua` | framebuffer subpixel 2×3 (triplica a resolução) |
| `palette.lua` | paletas e transição suave entre elas |
| `boot.lua` | a animação do amanhecer |
| `circuito.lua` | o diagrama vivo do circuito |
| `painel.lua` | o diagrama numa tela cheia, tocável |
| `rendimento.lua` | quanto do possível o sistema está tirando |
| `clima.lua` | aprende a curva do dia e infere a condição do céu |
| `soldemo.lua` | demo descartável, para conferir a base gráfica |
| `install.lua` | instalador: contém todos os acima, num paste só |

## A camada visual

`pixel.lua` usa os caracteres de teletext do CC para desenhar em 2×3 pontos por
caractere — num monitor 164×38 isso dá 328×114 pontos. Cada linha vira um
`blit` só, o que torna a animação viável em tela grande.

O amanhecer não redesenha o sol a cada quadro: ele muda a **paleta**, e a tela
inteira faz o fade a 10 chamadas por quadro.

> **Cuidado com a paleta:** ela é global no computador e persiste depois que o
> programa termina. Todo código que mexe nela roda dentro de `palette.com()`,
> que restaura as cores em qualquer caminho de saída — inclusive erro. Se você
> escrever algo novo que mexa em cores, use `palette.com`.

`painel.lua` num **Advanced Monitor** aceita toque: clique num bloco do diagrama
para ver os detalhes dele, clique de novo para fechar. Monitor comum não tem
toque.

## O sistema HELIOS

`startup.lua` roda sozinho quando o computador liga (é assim que o CC trata
esse nome). Ele faz uma **checagem real** de hardware — modems, medidor,
embreagem (lendo o seu `suntrack.cfg`), baterias e monitor — e depois abre um
menu que chama os programas.

Segure qualquer tecla durante a animação para pular direto para o menu.

A checagem não é enfeite: o que ela mostra é exatamente o que os programas vão
encontrar. Se o `suntrack` fosse falhar por falta de medidor, o boot já avisa.

## Instalar

Suba `install.lua` no <https://pastebin.com> e, no computador dentro do jogo:

```
pastebin run <codigo>
```

Isso grava `pgapi.lua`, `pgmon.lua` e `suntrack.lua` no computador. Um paste só.

Se preferir sem pastebin, `wget <url> install.lua` e depois `install` funciona igual —
qualquer URL que devolva texto puro serve (HTTP já está habilitado no perfil).

## O que o PowerGrid expõe ao computador

Confirmado lendo o jar do mod (`org.patryk3211.powergrid.compat.cc`):

| periférico | métodos |
|---|---|
| `powergrid_battery` | `capacity()` `energy()` `chargePercentage()` `powerDraw()` |
| `powergrid_voltage_gauge` | `voltage()` + base |
| `powergrid_current_gauge` | `current()` + base |
| `powergrid_power_gauge` | `power()` + base |
| `powergrid_energy_meter` | `energy()` `getValue()` `maxRange()` |
| `powergrid_generator_clutch` | `mode()` `load()` `rpm()` |
| `powergrid_redstone_converter` | `setValue(n)` `clearValue()` |

Base dos medidores: `getValue()` `maxRange()` `rangePercentage()`.

> **Pegadinha:** `chargePercentage()` e `rangePercentage()` devolvem **fração 0–1**,
> não 0–100, apesar do nome. `pgapi` já normaliza para 0–100 no campo `.pct`.

O painel solar e o bearing **não** são periféricos — não dá para ler o ângulo do
painel nem a geração dele direto. Por isso o rastreador usa os medidores.

**Como o Solar Panel Bearing funciona** (confirmado no bytecode): ele *consome
torque* do Create e *produz eletricidade*. O `buildCircuit` dele cria um
`CurrentSourceWire` — a parte elétrica é saída, não entrada. A rotação vem de
`getSpeed()`, a rede cinética do Create. Então para girar o painel o computador
não mexe em eletricidade nenhuma: ele controla o eixo, com redstone.

## pgmon — painel

Ligue ao computador com **Wired Modem + Networking Cable** (ou encostado direto no computador):

- um **monitor** (de preferência 3×2 ou maior, avançado para ter cor)
- os medidores e baterias que quiser acompanhar

```
pgmon        escala 0.5 (padrão)
pgmon 1      texto maior
```

Mostra geração total, baterias com barra e carga/descarga, medidores, geradores
(RPM e modo), energia acumulada, e um gráfico do histórico de potência.

Teclas: `Q` sai, `R` re-varre os periféricos, `G` liga/desliga o gráfico.
Tocar no monitor também re-varre.

## suntrack — rastreador solar

### Montagem

```
   fonte de rotacao (RPM baixo, 8-16)
              |  eixo
          Gearshift   <--- redstone do computador (inverte o sentido)
              |  eixo
           Clutch     <--- redstone do computador (liga/desliga)
              |  eixo
     Solar Panel Bearing  --gira-->  paineis solares
              |  saida eletrica
        Power Gauge  --wired modem + cabo-->  computador
```

1. **Fonte de rotação do Create** — motor, moinho, o que preferir. Use **RPM baixo,
   8 a 16**. Em RPM alto o menor pulso já passa do ponto e o rastreador oscila.
2. **Gearshift** no eixo (opcional, mas recomendado). Com redstone, inverte o
   sentido — é o que permite ao rastreador voltar quando passa do alvo.
3. **Clutch** no eixo, depois do gearshift. Com redstone, corta a rotação.
4. O eixo entra no **Solar Panel Bearing**, que gira os painéis.
5. **Power Gauge** na saída elétrica do bearing, ligado ao computador com
   **Wired Modem + Networking Cable** (clique no modem até acender).
6. O computador precisa alcançar o clutch e o gearshift **com redstone** —
   encostado, ou por fio saindo do lado configurado.

O clutch e o gearshift **não** precisam de modem: o computador tem saída de
redstone nativa. Só o medidor é periférico.

### Velocidade fina com Generator Clutch

Segundo a [wiki](https://createpowergrid.miraheze.org/wiki/Generator), o
**Generator Clutch** do PowerGrid entende sinal **analógico**: sinal cheio não
passa rotação nenhuma, sinal parcial limita o torque. Se você usar um no lugar
do Clutch do Create, ponha no `suntrack.cfg`:

```
clutchAnalog=1
runLevel=8
```

`runLevel` é o nível enviado ao girar (0 = torque total, 8 ≈ metade). Isso deixa
o painel girar mais devagar sem precisar baixar o RPM da fonte, o que dá passos
mais finos. Com o Clutch comum do Create deixe `clutchAnalog=0` — ele é apenas
liga/desliga.

### Estado seguro

O Clutch do Create para quando **recebe** redstone. Então, com o computador
desligado, o padrão é o painel girar sem parar. Se isso incomodar, ponha uma
tocha de redstone invertendo o sinal entre o computador e o clutch, e ponha
`invertClutch=1` no `suntrack.cfg` — aí "computador desligado" passa a
significar "painel travado".

### Como acha a melhor posição

Como o computador não consegue ler o ângulo, ele usa a própria geração como
realimentação — *perturb & observe*, o mesmo método dos rastreadores solares reais:

- **Amanhecer:** varredura completa de uma volta, guardando o pico visto. Depois
  gira até voltar a 95% desse pico. Isso acha o máximo global, não um local.
- **Durante o dia:** a cada 8 s confere. Se estiver bom, dá um passo curto e mede;
  se piorou mais que a banda morta de 2%, inverte o sentido (com gearshift) ou
  segue em frente até dar a volta (sem gearshift).
- **Queda grande** (12% abaixo do pico do dia): confere de novo 2 s depois antes de
  sair girando — chuva e nuvem derrubam a geração sem o painel ter saído do lugar.
- **Noite:** painel travado, confere a cada 20 s até amanhecer.

O alvo decai 0,1% por ciclo de propósito, senão a queda natural do fim de tarde
faria o programa rearmar a busca sem parar.

### Uso

```
suntrack testar    confere a montagem - rode este primeiro
suntrack           roda o rastreador
suntrack varrer    da uma volta medindo e mostra o pico
suntrack parar     trava o painel e sai
```

`Q` encerra. O painel é travado ao sair em qualquer caminho — inclusive se o
programa quebrar — senão ficaria girando para sempre.

### Ajustes

Crie um `suntrack.cfg` ao lado, uma chave por linha:

```
clutchSide=back
gearSide=right
sweepTime=35
```

`clutchSide` e `gearSide` são os lados do computador (`top`, `bottom`, `left`,
`right`, `front`, `back`). Deixe `gearSide` de fora se não usar gearshift.

`sweepTime` é quanto tempo o bearing leva para dar uma volta completa — rode
`suntrack varrer` e cronometre.

Outros: `pulse` duração do passo fino, `settle` espera antes de medir, `samples`
leituras promediadas, `deadband` banda morta, `reacquire` queda que dispara nova
busca, `nightPower` watts abaixo do qual conta como sem sol, `invertClutch`.

## Aprendizado diário e clima

Nenhum mod deste perfil expõe o clima ao computador — não existe sensor de
chuva. O único sensor é o próprio painel.

Então o sistema **aprende**: para cada hora do dia guarda a maior geração já
vista naquela hora (`.helios_curva`). Isso vira a curva de um dia limpo.
Comparando o agora com a curva, separa três coisas diferentes:

| leitura | significado |
|---|---|
| ≥ 70% do esperado para a hora | céu limpo |
| 25–70% | nublado |
| < 25% | chovendo, provavelmente |

**Isso muda uma decisão real:** debaixo de chuva o rastreador não gira. O
problema está no céu, não no ângulo — girar só gastaria energia atrás de sol
que não existe agora.

> **Limite honesto:** isto não distingue chuva de painel quebrado, obstruído ou
> fio solto. Diz "está gerando muito abaixo do que costuma nesta hora". A causa
> mais provável é o tempo, mas não é a única.

A curva só vale depois de alguns dias de sol. Antes disso o sistema diz
"aprendendo a curva do dia" em vez de inventar diagnóstico.

Ao anoitecer o dia é fechado: pico, média e condição vão para `.helios_dias`,
que guarda os últimos 14. O painel mostra como o último dia se saiu contra a
média dos anteriores.

## Rodar sozinho ao ligar

Para o painel subir junto com o computador, crie um `startup.lua`:

```lua
shell.run("pgmon")
```

Para o rastreador, use outro computador (os dois são laços infinitos).
