# Design — camada visual do HELIOS

Data: 2026-09-07
Sistema: CC:Tweaked 1.120.2 + PowerGrid 0.6.1 + Create 6.0.10, perfil *servidor de expresso*

## Objetivo

Dar ao HELIOS uma identidade visual: um boot com o sol nascendo, e um diagrama
do circuito real como tela principal do painel, com a energia correndo pelas
linhas e a bateria enchendo em tempo real.

O diagrama não é enfeite. A meta é uma tela que o jogador olha para *saber como
o sistema está*, não só para achar bonito.

## Decisões tomadas

| decisão | escolha | por quê |
|---|---|---|
| identidade | solar no boot, blueprint vivo nas telas | o boot dá o impacto (visto uma vez), o diagrama dá utilidade (visto sempre) |
| destino | monitor grande, 6×4 ou maior | o diagrama precisa de espaço; o código lê `getSize()` e adapta |
| repetição do boot | completo na 1ª vez, curto depois | animação longa vira estorvo a partir da vigésima vez |
| técnica | híbrido: subpixel onde compensa | evita o artefato de 2 cores por célula justamente onde ele apareceria |

## Capacidades do CC confirmadas

Verificadas no jar `cc-tweaked-1.21.1-forge-1.120.2.jar`:

- `term.setPaletteColour(cor, r, g, b)` — as 16 cores são redefiníveis.
- `term.getPaletteColour` e `term.nativePaletteColour` — dá para ler a atual e a
  original, então dá para restaurar com precisão.
- `term.blit(texto, fg, bg)` — uma linha inteira com cor por caractere.
- `paintutils.loadImage` / `drawImage` — pixel art `.nfp` (não usado neste design,
  mas disponível).
- Caracteres de teletext na fonte do terminal — subpixel 2×3 por célula.

## Arquitetura

Três bibliotecas novas. Cada uma tem uma responsabilidade e é testável sozinha.

```
pgapi.lua ──────────┐
                    ├──> circuito.lua ──┐
pixel.lua ──────────┤                   ├──> pgmon.lua
                    ├──> boot.lua ──────┴──> startup.lua
palette.lua ────────┘
ui.lua (inalterada) ─────────────────────> todos
```

`ui.lua` continua como está. As libs novas **somam**; nada do que já funciona é
reescrito.

## Componentes

### pixel.lua — framebuffer subpixel

Mantém um buffer de pontos de `largura×2` por `altura×3` e converte para
caracteres de teletext na hora de enviar.

```lua
local fb = pixel.novo(tela)
fb.w, fb.h              -- dimensões em pontos
fb:limpar(cor)
fb:ponto(x, y, cor)
fb:linha(x1, y1, x2, y2, cor)
fb:retangulo(x, y, w, h, cor, preenchido)
fb:circulo(cx, cy, r, cor, preenchido)
fb:enviar()             -- converte e faz blit, uma chamada por linha
```

**A conversão.** Cada célula do terminal cobre 6 pontos, dispostos assim:

```
 bit0  bit1
 bit2  bit3
 bit4  bit5
```

Os caracteres 128–159 representam as 32 combinações dos **cinco primeiros**
pontos, sobre um par de cores (frente e fundo). O sexto ponto não tem caractere
próprio: ele é obtido invertendo as duas cores e usando o caractere
complementar.

O algoritmo por célula:

1. Ler as 6 cores dos pontos.
2. Escolher as duas mais frequentes. Se houver só uma, o caractere é um espaço
   sólido. Se houver mais de duas, cada cor sobrante é absorvida pela vencedora
   mais próxima **em distância RGB** — comparando os valores da paleta corrente,
   não os índices de cor, porque os índices não têm ordem visual. É aqui que
   mora o artefato conhecido.
3. Montar o bitmask de 6 bits marcando quais pontos são da cor de frente.
4. Se o bit5 estiver marcado, inverter: trocar frente e fundo e complementar o
   bitmask (`bits = 31 - (bits & 31)`).
5. Emitir caractere `128 + bits` e o par de cores.

Uma linha inteira vira um `blit`. Num monitor 6×4 (~4.800 células) isso é ~40
chamadas por quadro em vez de ~4.800.

**Limitação aceita:** duas cores por célula. Onde três ou mais cores se encontram
no mesmo caractere, uma perde. Por isso o subpixel é usado só no disco do sol
(tons vizinhos) e nas linhas do circuito (fundo uniforme).

### palette.lua — paletas e fade

```lua
palette.PALETAS.noite / .amanhecer / .dia   -- cor -> {r, g, b} em 0..1
palette.aplicar(tela, paleta)
palette.tween(tela, de, para, t)            -- t de 0 a 1, interpola RGB
palette.guardar(tela)                       -- salva a paleta atual
palette.restaurar(tela)                     -- volta ao que estava
```

`guardar` lê as 16 cores com `getPaletteColour` antes de qualquer mudança.
`restaurar` reescreve exatamente aquelas — não assume que o padrão do CC é o que
estava lá, porque outro programa pode ter mexido.

### boot.lua — o amanhecer

```lua
boot.rodar(tela, modo)     -- modo = "completo" (~6s) ou "curto" (~1,5s)
boot.jaViu()               -- lê o arquivo de estado
boot.marcarVisto()
```

Sequência do modo completo:

1. Céu noturno, estrelas esparsas. Paleta `noite`.
2. O disco do sol sobe pela borda inferior, desenhado com `pixel.lua`.
3. Enquanto sobe, a paleta faz `tween` de `noite` para `amanhecer` e depois para
   `dia`, em ~40 passos. **O sol não é redesenhado a cada quadro** — só a paleta
   muda, a 8 chamadas por quadro.
4. Raios pulsam (esses sim redesenhados, é pouca área).
5. "H E L I O S" aparece, e a tela cede lugar à checagem de hardware.

O modo curto pula direto para o passo 3 com menos passos de tween.

Estado em `.helios_boot` na raiz do computador. Ausente = primeira vez.

Qualquer tecla pula a animação em ambos os modos — o vigia de tecla vive só
durante a animação, nunca durante o menu (bug já corrigido no `startup.lua`
atual, e a regra se mantém).

### circuito.lua — o diagrama vivo

```lua
circuito.desenhar(fb, tela, dados)
-- dados = { geracao =, unidade =, bateriaPct =, estado =, girando = }
```

Desenha os quatro blocos do circuito real (bearing, medidor, bateria,
computador) ligados por linhas, e sobre as linhas faz correr pontos animados
cuja **velocidade é proporcional à corrente medida**. Sem geração, os pontos
param — a tela mostra o estado sem precisar ler número nenhum.

A bateria é um retângulo que enche conforme a carga, com a mesma escala de cor
já usada no `pgmon` (verde / laranja / vermelho).

Números reais ficam ao lado do diagrama, em texto normal via `ui.lua`.

Se a tela for pequena demais para o diagrama completo (menos de 40 colunas), cai
para uma versão de três blocos numa linha só.

## Fluxo de dados

```
pgapi.scan/read  →  dados  →  circuito.desenhar  →  pixel:enviar  →  term.blit
                                     ↑
                              palette (cores)
```

Uma leitura por quadro, no máximo 10 quadros por segundo.

## Tratamento de erros

**A paleta é global e persiste.** Se um programa morrer sem restaurar, o shell,
o `edit` e todo o resto ficam com as cores erradas até o computador reiniciar.
Tratamento igual ao do motor no `suntrack`: `guardar` no início, `restaurar` em
`pcall` de saída, em **todos** os caminhos — saída normal, tecla Q, erro,
`Ctrl+T`. Coberto por teste.

**Sem cor.** Se `isColour()` for falso (computador comum), `pixel.lua` funciona
em preto e branco e `palette` vira no-op. Nada quebra, só fica monocromático.

**Tela pequena.** O `circuito` simplifica; o `boot` reduz o sol proporcionalmente.

**Periférico sumindo no meio.** Já tratado por `pgapi.try`; o diagrama desenha o
bloco em cinza quando a leitura vem `nil`.

## Testes

Somados à suíte atual (48 casos, todos passando):

- **pixel:** conversão de padrões conhecidos de 6 pontos para caractere e par de
  cores, incluindo o caso de inversão pelo bit5 e o caso de três cores na mesma
  célula.
- **palette:** `tween` nos extremos (t=0 e t=1) e no meio; `restaurar` devolve
  exatamente as cores lidas por `guardar`.
- **boot:** roda nos dois modos sem erro; restaura a paleta ao sair em todos os
  caminhos, inclusive quando interrompido no meio.
- **circuito:** renderiza com geração zero, geração alta, bateria cheia, bateria
  vazia, e com periférico devolvendo `nil`.
- **visual:** as telas renderizadas no simulador com cores, para conferência de
  layout antes de instalar — foi o que pegou as duas colisões de texto da vez
  passada.

## Fora de escopo

- Som (o CC tem `speaker`, mas não foi pedido).
- Rastreamento por cálculo de posição solar — o `suntrack` continua com o método
  perturb & observe atual; este trabalho é só visual.
- Reescrita da `ui.lua` — ela continua servindo texto, barras e menus.
- Formato `.nfp` / `paintutils` — o sol é gerado por código, não carregado de
  arquivo, para poder escalar com o tamanho da tela.

## Ordem de implementação

1. `pixel.lua` + testes de conversão (é a base de tudo).
2. `palette.lua` + teste de restauração (é o maior risco).
3. `boot.lua`, integrado ao `startup.lua`.
4. `circuito.lua`, integrado ao `pgmon.lua`.
5. Renderização visual de conferência e instalação no mundo.

Cada etapa é instalável sozinha — dá para parar em qualquer ponto com o sistema
funcionando.
