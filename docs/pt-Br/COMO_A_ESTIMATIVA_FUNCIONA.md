# Como o app prevê o peso do GIF antes de converter

Este documento explica o modelo por trás do número que aparece no rodapé do
editor — e, no fim, dá as receitas práticas para escolher configurações sem
precisar entender nada disso.

---

## Por que dá para prever

Um GIF é uma sequência de quadros em que cada quadro é uma imagem de no
máximo 256 cores comprimida com LZW. Além disso, o FFmpeg regrava apenas o
retângulo que mudou de um quadro para o outro (`diff_mode=rectangle`).

Isso divide os quadros em duas espécies com preços bem diferentes. O
**primeiro** é uma imagem completa, porque não existe quadro anterior para
comparar. Os **demais** custam só o retângulo que mudou. Na prática, o peso
segue muito bem esta conta:

```
bytes  ≈  cabeçalho + paleta
          +  largura × altura × k_chave
          +  (quadros − 1) × largura × altura × k_delta
```

> **Por que dois `k` e não um.** Tratar todos os quadros como se custassem o
> mesmo parece inofensivo, e é — até você medir 1 segundo e prever 40. Numa
> cena parada o primeiro quadro é praticamente o arquivo inteiro: diluído
> entre 12 quadros da amostra ele parece caríssimo, e multiplicar isso por
> 517 quadros produz uma previsão dez vezes maior que o arquivo real. Foi
> exatamente esse o defeito da primeira versão do modelo, e ele aparecia
> justamente no tipo de vídeo mais comum de virar GIF: cartão de título,
> gravação de tela, print animado. Os números estão em
> [Precisão medida](#precisão-medida).

Tudo aí é conhecido antes de converter — **menos os dois `k`**, que são quanto
cada pixel custa em bytes. E eles dependem de duas coisas bem diferentes:

| | O que é | Dá para saber antes? |
|---|---|---|
| **Conteúdo** | quanto a cena se mexe e quanto detalhe ela tem | ❌ só medindo |
| **Configuração** | fps, cores, dither, escala, velocidade | ✅ é só calcular |

A ideia central do modelo é **separar as duas**. Assim o conteúdo precisa ser
medido só uma vez por vídeo, e continua valendo enquanto o usuário mexe em
todos os controles.

---

## As duas metades de cada `k`

```
k = complexidade_do_vídeo × fator_das_configurações
```

### A complexidade (medida uma vez)

É um número em bytes por pixel por quadro, expresso em **condições de
referência**: 12 fps, 256 cores, dither equilibrado, paleta única, velocidade
1x e imagem reduzida à metade da largura original.

Valores típicos:

| Tipo de vídeo | complexidade |
|---|---|
| Pessoa falando, câmera parada | 0,05 – 0,10 |
| Cena comum de celular | 0,12 – 0,20 |
| Câmera em movimento, muita textura | 0,25 – 0,40 |
| Confete, fogos, água, chuva | 0,40 + |

Enquanto o usuário não toca em "Medir", o app usa um palpite tirado do
bitrate do arquivo original (bitrate alto por pixel = cena mais complexa).
É um palpite razoável, com margem de erro anunciada de ±40–55%.

### O fator das configurações (calculado)

Cada controle vira um multiplicador. Todos valem 1,0 nas condições de
referência:

| Controle | Fórmula | Vale para o 1º quadro? | Por quê |
|---|---|---|---|
| FPS | `(12 / fps) ^ 0,30` | ❌ | mais quadros = mais parecidos entre si, então cada um custa menos |
| Cores | `(cores / 256) ^ 0,45` | ✅ | menos símbolos distintos comprime melhor |
| Dither | tabela: 0,72 a 1,55 | ✅ | pontilhado é ruído, e ruído comprime mal |
| Paleta | 0,95 a 1,30 | ✅ | paleta por quadro impede reaproveitar a tabela de cores |
| Velocidade | `velocidade ^ 0,12` | ❌ | acelerar aumenta a diferença entre quadros vizinhos |
| Escala | `(redução / 0,5) ^ 0,12` | ✅ | encolher também suaviza detalhe e ruído |

FPS e velocidade não entram no primeiro quadro de propósito: ele é uma imagem
parada, e uma imagem parada não fica mais barata porque o vídeo tem mais
quadros por segundo.

Os expoentes fracionários são o detalhe que faz o modelo funcionar. **Dobrar
o FPS não dobra o arquivo** — aumenta cerca de 62%, porque metade dos quadros
novos é quase idêntica ao quadro anterior. Um modelo linear erraria feio
justamente no controle que as pessoas mais mexem.

---

## O botão "Medir"

Quando o usuário toca em **Medir**, o app:

1. escolhe 2 pontos dentro do trecho selecionado (a 20% e a 60%);
2. converte de verdade uma janela de menos de 1 segundo em cada ponto, com as
   **mesmas** configurações escolhidas;
3. converte a mesma janela **uma segunda vez, cortada no primeiro quadro**,
   reaproveitando a paleta que acabou de gerar (por isso sai quase de graça);
4. mede o tamanho real dos dois arquivos. A diferença entre eles é, por
   construção, o que os quadros seguintes custaram;
5. **inverte a fórmula** para descobrir as duas complexidades do vídeo:

   ```
   k_chave = (bytes_1_quadro − cabeçalho) / (largura × altura)
             ÷ fator_das_configurações_do_quadro_parado

   k_delta = (bytes_janela − bytes_1_quadro) / ((quadros − 1) × largura × altura)
             ÷ fator_das_configurações
   ```

6. combina as duas amostras com peso maior para a mais pesada — errar para
   cima incomoda menos do que prometer 3 MB e entregar 12 MB.

É a terceira codificação que torna o modelo honesto: sem ela não há como
separar o quadro caro dos quadros baratos, e o custo do primeiro acaba
espalhado por todos.

Custa 2 a 5 segundos e derruba a margem de erro anunciada de ±55% para ±15%.

E, porque a complexidade é independente das configurações, **o usuário pode
continuar mexendo em todos os controles depois de medir** sem precisar medir
de novo. Essa é a razão de o modelo ser construído dessa forma.

Na tela de resultado o app mostra a diferença entre o previsto e o real. Se
esse número ficar sistematicamente alto para um tipo de vídeo, é sinal de que
algum expoente da tabela acima merece ajuste.

---

## Precisão medida

O modelo não é avaliado por opinião. `tool/medir_precisao.py` gera cinco
vídeos sintéticos que cobrem os extremos de complexidade, converte cada um
com a mesma cadeia de filtros do app e guarda os tamanhos reais; o teste
`test/size_estimator_medicoes_test.dart` alimenta o modelo com essas medições
e compara a previsão com o arquivo que realmente saiu.

Saída de 400×224 px, 12 FPS, 256 cores, dither equilibrado, 43,1 s
(517 quadros), calibrada com duas amostras de 1 segundo:

| Vídeo | Real | Previsto | Erro | Modelo antigo |
|---|---|---|---|---|
| Cartão de título (estático) | 0,04 MB | 0,02 MB | −44% | **+1683%** |
| Fundo parado, objeto se movendo | 0,42 MB | 0,43 MB | +1% | +56% |
| Cena agitada | 5,29 MB | 5,32 MB | +1% | +6% |
| Gradiente em movimento | 17,81 MB | 16,62 MB | −7% | −6% |
| Ruído (incompressível) | 42,80 MB | 42,98 MB | +0% | +1% |

Três leituras importantes:

- **O modelo antigo não era ruim em tudo.** Ele acertava cenas cheias de
  movimento, onde o primeiro quadro é um detalhe no meio de centenas. Ele
  quebrava quanto mais parada fosse a imagem — e cartão de título, gravação
  de tela e print animado são justamente os vídeos que mais viram GIF.
- **O cartão de título continua fora dos ±15%, e tudo bem.** O arquivo tem
  39 KB: errar 17 KB para baixo vira −44% na porcentagem e nada na prática.
  A régua relativa não diz muita coisa nessa escala, e por isso o teste cobra
  erro *absoluto* abaixo de 100 KB e erro *relativo* acima.
- **O gradiente erra os mesmos −7% nos dois modelos**, o que é esperado: o
  problema dele não é o primeiro quadro, é que gradiente em movimento é o
  conteúdo que menos se parece com o resto de si mesmo ao longo do tempo. É
  o próximo lugar onde o modelo tem folga para melhorar.

As medições são reproduzíveis: as fontes têm semente e cores fixas e são
codificadas com `-threads 1`, porque tanto o filtro `gradients` quanto o x264
multi-thread variam de uma execução para outra e fariam o teste oscilar.

Para refazer as medições (precisa de `ffmpeg` e `ffprobe` no PATH):

```bash
python3 tool/medir_precisao.py
```

Ele imprime a tabela e o bloco de constantes pronto para colar no teste.

## Os testes

`test/size_estimator_test.dart` cobre:

- **monotonicidade** — mexer cada controle na direção esperada muda o peso na
  direção esperada;
- **sublinearidade do FPS** — dobrar o FPS aumenta o peso entre 30% e 100%,
  nunca mais que isso;
- **ida e volta da calibração** — estimar com uma complexidade conhecida e
  depois recuperá-la a partir do resultado devolve os mesmos dois números;
- **independência de configuração** — uma complexidade medida a 12 fps / 480 px
  prevê corretamente um GIF a 20 fps / 320 px (erro < 5%);
- **independência de duração** — uma cena praticamente parada medida em 1
  segundo prevê corretamente uma conversão de 40 segundos (erro < 5%). É o
  teste que trava o defeito do primeiro quadro diluído;
- **robustez** — medições absurdas caem no valor padrão em vez de quebrar;
- **ajuste automático** — a busca por um alvo de tamanho sempre termina e
  nunca altera o trecho escolhido pelo usuário.

```bash
flutter test
```

---

## Receitas práticas (a parte que interessa no dia a dia)

### Qual controle mexer primeiro

Em ordem de "quanto economiza por quanto estraga":

1. **Duração** — efeito direto e sem perda de qualidade. Metade da duração,
   metade do peso. É quase sempre a melhor jogada.
2. **Resolução** — efeito ao quadrado. De 480 px para 240 px o arquivo fica
   **4 vezes** menor. A perda é visível, mas GIF costuma ser visto pequeno.
3. **FPS** — de 24 para 12 quase ninguém percebe num GIF, e economiza ~38%.
   Abaixo de 8 fps começa a "engasgar".
4. **Cores** — 128 cores passam despercebidas em muita cena. Abaixo de 64
   começa a aparecer faixa em céu e pele.
5. **Dither** — mexa por último. É o que mais estraga gradientes.

### Combinações que funcionam

| Objetivo | Largura | FPS | Cores | Dither | Peso típico (5s) |
|---|---|---|---|---|---|
| Sticker / reação de WhatsApp | 240 px | 12 | 128 | Leve | 300 KB – 1 MB |
| Post de rede social | 480 px | 12 | 256 | Equilibrado | 1,5 – 4 MB |
| Demonstração de tela / tutorial | 640 px | 10 | 64 | Sem pontilhado | 1 – 3 MB |
| Qualidade máxima, peso livre | 720 px | 20 | 256 | Alta | 10 – 30 MB |

### Casos especiais

- **Gravação de tela, desenho, texto:** use **"Sem pontilhado"** e poucas
  cores. Essas imagens têm áreas chapadas, que comprimem muito bem — o dither
  só atrapalharia. Dá para chegar em arquivos minúsculos com qualidade
  perfeita.
- **Céu, fumaça, sombras, pele:** são gradientes, o pior caso do GIF. Aqui
  vale subir o dither para "Alta" e aceitar o arquivo maior — ou reduzir a
  resolução, o que disfarça o problema.
- **Fundo parado com um objeto se mexendo:** experimente a paleta **"Focada
  no movimento"**.
- **Cena que muda completamente no meio:** a paleta única vai errar as cores
  em uma das metades. Ou use **"Paleta por quadro"**, ou — melhor — corte em
  dois GIFs.

### Como saber se o peso está bom

O app já classifica, mas a régua é esta:

| Peso | Classificação | Na prática |
|---|---|---|
| até 2 MB | Leve | envia em qualquer lugar |
| 2 – 6 MB | Bom | confortável em redes sociais e WhatsApp |
| 6 – 15 MB | Pesado | demora para carregar, alguns apps recomprimem |
| acima de 15 MB | Muito pesado | vários apps recusam ou destroem a qualidade |

E o dado mais útil de todos: **peso por segundo**. Se um GIF está em 2 MB/s,
nenhum ajuste de cor vai salvar — o caminho é cortar a duração ou a
resolução.
