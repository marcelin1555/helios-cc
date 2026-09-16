# HELIOS — painel PowerGrid + rastreador solar (CC:Tweaked)

Programas para o perfil *servidor de expresso* (CC:Tweaked 1.120.2 + PowerGrid 0.6.1).

| arquivo | o que é |
|---|---|
| `startup.lua` | boot do sistema HELIOS: checagem de hardware + menu |
| `pgapi.lua` | biblioteca: descobre e lê os periféricos do PowerGrid |
| `ui.lua` | biblioteca de interface: telas, barras, menus |
| `config.lua` | leitura/escrita de `helios.cfg` — o lugar único de configuração |
| `configurar.lua` | assistente que descobre a rede e escreve `helios.cfg` |
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

## Configuração — um lugar só

Tudo que depende da **sua** montagem — qual medidor ler, onde estão a
embreagem e o câmbio, qual monitor usar, quantos painéis existem — mora em
`/helios.cfg`. Nenhum outro programa guarda ajuste próprio; todos leem daqui.

O jeito fácil é rodar o assistente, que já lista o que existe na rede:

```
configurar
```

Ele pergunta, com listas de escolha:
- **qual medidor** acompanha o painel (ou "automático");
- **qual monitor** usar (ou "nenhum", para ficar só na tela do computador);
- **onde está a embreagem** — direto no computador ou num Redstone Relay da
  rede — com um teste que acende um lado por vez para você identificar;
- **onde está o câmbio** (mesma escolha, ou "nenhum" se não tiver);
- se a embreagem é invertida ou analógica (Generator Clutch);
- **quantos painéis** tem, para comparar com o catálogo.

O arquivo gerado é Lua comentado — dá para editar na mão com `edit helios.cfg`
se preferir, ou ajustar um número sem rodar o assistente de novo.

> Quem já tinha `suntrack.cfg`/`painel.cfg` (versão antiga) não perde a
> montagem: na primeira leitura sem `helios.cfg`, o sistema converte os
> arquivos antigos e já grava o novo — os antigos ficam só como histórico,
> podem ser apagados.

## Redstone pela rede — o equipamento para girar o painel

A embreagem (Clutch) e o câmbio (Gearshift) do Create **não são periféricos**:
um Wired Modem colado neles, sozinho, não expõe nada ao computador. O que os
alcança de longe, pela mesma rede de cabo do medidor, é o
**Redstone Relay** do próprio CC:Tweaked — um bloco com Wired Modem embutido
que leva sinal de redstone pela rede.

```
computador ──cabo + wired modem──┬── Redstone Relay ── embreagem (Clutch)
                                  ├── Redstone Relay ── câmbio (Gearshift)
                                  └── Wired Modem ────── medidor
```

Cole um Redstone Relay em cada bloco (ou reaproveite um só, se dois lados dele
alcançarem os dois blocos), ligue-os na mesma rede de cabo do medidor, e no
`configurar` escolha o relay em vez de "direto no computador". Isso substitui
qualquer solução sem fio (Redstone Link do Create) ou fio de redstone correndo
pelo mapa — tudo vai pela mesma rede de cabo.

Sem relay nenhum, ainda dá para usar **"direto no computador"**: aí o
computador manda redstone nativo, e a embreagem precisa estar encostada nele
ou ligada por fio de redstone comum (ou por Redstone Link, que também
funciona, só que sem fio).

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
embreagem (lendo o seu `helios.cfg`), baterias e monitor — e depois abre um
menu que chama os programas, incluindo "Configurar a montagem".

Segure qualquer tecla durante a animação para pular direto para o menu.

A checagem não é enfeite: o que ela mostra é exatamente o que os programas vão
encontrar. Se o `suntrack` fosse falhar por falta de medidor, o boot já avisa —
e se a embreagem nunca foi configurada, ele diz para rodar `configurar`.

## Instalar

O código vive em <https://github.com/marcelin1555/helios-cc>. No computador
dentro do jogo:

```
wget run https://raw.githubusercontent.com/marcelin1555/helios-cc/main/install.lua
```

Isso grava todos os arquivos do sistema no computador, na ordem certa. Depois,
rode `configurar` uma vez e reinicie com `Ctrl+R`.

Funciona em qualquer mundo/servidor com a API `http` do CC habilitada — o
`raw.githubusercontent.com` não pede autenticação, então serve tanto para o
save local quanto para um servidor de terceiros. Se preferir sem baixar toda
vez, `wget https://raw.githubusercontent.com/marcelin1555/helios-cc/main/install.lua install.lua`
salva o arquivo e depois `install` roda quantas vezes quiser.

### Atualizar

Depois de mudar algo no repositório, rode o mesmo `wget run` de novo — ele
sobrescreve os arquivos existentes. O `helios.cfg` não é tocado pelo
instalador, então a sua montagem não se perde numa atualização.

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

O monitor usado é o que estiver em `helios.cfg` (`configurar` deixa escolher);
sem configuração, pega o primeiro monitor encontrado.

Mostra geração total, baterias com barra e carga/descarga, medidores, geradores
(RPM e modo), energia acumulada, e um gráfico do histórico de potência.

Teclas: `Q` sai, `R` re-varre os periféricos, `G` liga/desliga o gráfico.
Tocar no monitor também re-varre.

## suntrack — rastreador solar

### Montagem

```
   fonte de rotacao (RPM baixo, 8-16)
              |  eixo
          Gearshift   <--- redstone (rele ou nativo, configurado)
              |  eixo
           Clutch     <--- redstone (rele ou nativo, configurado)
              |  eixo
     Solar Panel Bearing  --gira-->  paineis solares
              |  saida eletrica
        Current Gauge  --wired modem + cabo-->  computador
```

1. **Fonte de rotação do Create** — motor, moinho, o que preferir. Use **RPM baixo,
   8 a 16**. Em RPM alto o menor pulso já passa do ponto e o rastreador oscila.
2. **Gearshift** no eixo (opcional, mas recomendado). Com redstone, inverte o
   sentido — é o que permite ao rastreador voltar quando passa do alvo.
3. **Clutch** no eixo, depois do gearshift. Com redstone, corta a rotação.
4. O eixo entra no **Solar Panel Bearing**, que gira os painéis.
5. Um **medidor** no circuito elétrico do bearing, ligado por **Wired Modem +
   Networking Cable**. Prefira o **Current Gauge**: ele tem 2 terminais e vai
   em série, enquanto o Power Gauge tem 3 (shunt em série + referência de
   tensão). Para rastrear o sol a corrente serve tão bem quanto a potência.

   O medidor tem terminal **+** e **−**, e vai em série — a corrente entra pelo
   `+` e sai pelo `−`. A cadeia fica assim:

   ```
   bearing +  ->  gauge +
   gauge -    ->  bateria +
   bateria -  ->  bearing -
   ```

   O circuito precisa estar **fechado**, com uma carga (bateria, resistor,
   lâmpada) no caminho de volta ao bearing. Sem carga não circula corrente e o
   medidor lê zero. Ligar os dois terminais do gauge no mesmo polo é
   curto-circuito — o gauge tem resistência quase zero e queima.
6. **Redstone Relay + Wired Modem** colado na embreagem, e outro no câmbio (ou
   o mesmo relay, se dois lados dele alcançarem os dois blocos). Ligue-os na
   mesma rede de cabo do medidor. Veja a seção **Redstone pela rede** acima.

Depois de montar, rode `configurar` para dizer onde está cada coisa.

### Velocidade fina com Generator Clutch

Segundo a [wiki](https://createpowergrid.miraheze.org/wiki/Generator), o
**Generator Clutch** do PowerGrid entende sinal **analógico**: sinal cheio não
passa rotação nenhuma, sinal parcial limita o torque. No `configurar`, marque
"é um Generator Clutch" e informe o nível ao girar (0 = torque total, 8 ≈
metade). Isso deixa o painel girar mais devagar sem precisar baixar o RPM da
fonte, o que dá passos mais finos. Com o Clutch comum do Create, deixe
desmarcado — ele é apenas liga/desliga.

### Estado seguro

O Clutch do Create para quando **recebe** redstone. Então, com o computador
desligado, o padrão é o painel girar sem parar. Se isso incomodar, ponha uma
tocha de redstone invertendo o sinal entre o relé (ou o computador) e o
clutch, e marque "há uma tocha invertendo o sinal" no `configurar` — aí
"computador desligado" passa a significar "painel travado".

### Como acha a melhor posição

Como o computador não consegue ler o ângulo, ele usa a própria geração como
realimentação — *perturb & observe*, o mesmo método dos rastreadores solares reais:

- **Amanhecer:** varredura completa de uma volta, guardando o pico visto. Depois
  gira até voltar a 95% desse pico. Isso acha o máximo global, não um local.
- **Durante o dia:** a cada 8 s confere. Se estiver bom, dá um passo curto e mede;
  se piorou mais que a banda morta de 2%, inverte o sentido (com câmbio) ou
  segue em frente até dar a volta (sem câmbio).
- **Queda grande** (35% abaixo do pico do dia): confere de novo antes de sair
  girando, e só varre de novo se a queda persistir por 3 leituras seguidas **e**
  já tiver passado o tempo mínimo entre buscas (90 s por padrão). Um gatilho
  baixo (12%, testado antes) disparava à toa toda manhã e tarde, quando a queda
  é só o sol baixo no céu — girar não traz essa energia de volta.
- **Chuva:** se a curva do dia já foi aprendida (ver `clima.lua` abaixo) e a
  geração está muito abaixo do normal daquela hora, o rastreador entende que o
  problema é o céu, não o ângulo, e **não gira** — só espera.
- **Bateria cheia:** a corrente cai porque a tensão da bateria encostou na do
  painel, não porque ele saiu de posição. O rastreador trava e não sai
  procurando.
- **Noite:** painel travado, confere a cada 20 s até amanhecer.

O alvo decai 0,1% por ciclo de propósito, senão a queda natural do fim de tarde
faria o programa rearmar a busca sem parar.

### Uso

```
configurar         assistente que descobre a rede e escreve helios.cfg
suntrack testar    confere a montagem - rode isso depois de configurar
suntrack           roda o rastreador
suntrack varrer    da uma volta medindo e mostra o pico
suntrack parar     trava o painel e sai
```

`Q` encerra. O painel é travado ao sair em qualquer caminho — inclusive se o
programa quebrar — senão ficaria girando para sempre.

### Ajustes finos

Os números de `rastreio` em `helios.cfg` (pulso, banda morta, tempo de
varredura etc.) dão para editar na mão com `edit helios.cfg` — o arquivo é
comentado. O mais importante é `volta`: quanto tempo o bearing leva para dar
uma volta completa. Rode `suntrack varrer` e cronometre para acertar o número.

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

`startup.lua` já é o que sobe sozinho — é o próprio HELIOS. Se quiser que o
menu abra direto no painel visual em vez de esperar escolha, edite o item 1 do
menu em `startup.lua` para chamar `painel` automaticamente.

Para rodar o rastreador *e* o painel visual ao mesmo tempo, use dois
computadores — os dois são laços infinitos e não dividem tela.
