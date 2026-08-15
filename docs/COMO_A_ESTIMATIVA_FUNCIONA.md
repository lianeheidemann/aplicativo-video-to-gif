# Como o app prevê o peso do GIF antes de converter

Este documento explica o modelo por trás do número que aparece no rodapé do
editor — e, no fim, dá as receitas práticas para escolher configurações sem
precisar entender nada disso.

---

## Por que dá para prever

Um GIF é uma sequência de quadros em que cada quadro é uma imagem de no
máximo 256 cores comprimida com LZW. Além disso, o FFmpeg regrava apenas o
retângulo que mudou de um quadro para o outro (`diff_mode=rectangle`).

Na prática, o peso segue muito bem esta conta:

```
bytes  ≈  cabeçalho + paleta  +  quadros × largura × altura × k
```

Tudo aí é conhecido antes de converter — **menos o `k`**, que é quanto cada
pixel custa em bytes. E o `k` depende de duas coisas bem diferentes:

| | O que é | Dá para saber antes? |
|---|---|---|
| **Conteúdo** | quanto a cena se mexe e quanto detalhe ela tem | ❌ só medindo |
| **Configuração** | fps, cores, dither, escala, velocidade | ✅ é só calcular |

A ideia central do modelo é **separar as duas**. Assim o conteúdo precisa ser
medido só uma vez por vídeo, e continua valendo enquanto o usuário mexe em
todos os controles.

---

## As duas metades do `k`

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

| Controle | Fórmula | Por quê |
|---|---|---|
| FPS | `(12 / fps) ^ 0,30` | mais quadros = mais parecidos entre si, então cada um custa menos |
| Cores | `(cores / 256) ^ 0,45` | menos símbolos distintos comprime melhor |
| Dither | tabela: 0,72 a 1,55 | pontilhado é ruído, e ruído comprime mal |
| Paleta | 0,95 a 1,30 | paleta por quadro impede reaproveitar a tabela de cores |
| Velocidade | `velocidade ^ 0,12` | acelerar aumenta a diferença entre quadros vizinhos |
| Escala | `(redução / 0,5) ^ 0,12` | encolher também suaviza detalhe e ruído |

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
3. mede o tamanho real dos arquivos gerados;
4. **inverte a fórmula** para descobrir a complexidade do vídeo:

   ```
   complexidade = (bytes_medidos − cabeçalho) / (quadros × largura × altura)
                  ÷ fator_das_configurações
   ```

5. combina as duas amostras com peso maior para a mais pesada — errar para
   cima incomoda menos do que prometer 3 MB e entregar 12 MB.

Custa 2 a 5 segundos e derruba a margem de erro anunciada de ±55% para ±15%.

E, porque a complexidade é independente das configurações, **o usuário pode
continuar mexendo em todos os controles depois de medir** sem precisar medir
de novo. Essa é a razão de o modelo ser construído dessa forma.

Na tela de resultado o app mostra a diferença entre o previsto e o real. Se
esse número ficar sistematicamente alto para um tipo de vídeo, é sinal de que
algum expoente da tabela acima merece ajuste.

---

## Os testes

`test/size_estimator_test.dart` cobre:

- **monotonicidade** — mexer cada controle na direção esperada muda o peso na
  direção esperada;
- **sublinearidade do FPS** — dobrar o FPS aumenta o peso entre 30% e 100%,
  nunca mais que isso;
- **ida e volta da calibração** — estimar com uma complexidade conhecida e
  depois recuperá-la a partir do resultado devolve o mesmo número;
- **independência de configuração** — uma complexidade medida a 12 fps / 480 px
  prevê corretamente um GIF a 20 fps / 320 px (erro < 5%);
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
