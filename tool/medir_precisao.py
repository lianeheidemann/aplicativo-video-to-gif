#!/usr/bin/env python3
"""Mede a precisão real do modelo de estimativa de peso.

Gera vídeos sintéticos que cobrem os extremos de complexidade de uma cena,
converte cada um em GIF com EXATAMENTE a mesma cadeia de filtros que o app usa
(`fps` -> `scale=lanczos` -> `palettegen`/`paletteuse` com
`diff_mode=rectangle`) e imprime, para cada vídeo:

  - o tamanho real da conversão inteira;
  - as duas amostras de 1 segundo que o app usaria para calibrar, cada uma com
    o tamanho do GIF da janela e o do mesmo GIF cortado no primeiro quadro.

A saída inclui o bloco de constantes pronto para colar em
`test/size_estimator_medicoes_test.dart`, que é onde esses números viram
teste de regressão.

Rode a partir da raiz do projeto (precisa de ffmpeg e ffprobe no PATH):

    python3 tool/medir_precisao.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

# Mesmas condições do teste de regressão.
FPS = 12
CORES = 256
LARGURA = 400
DITHER = 'bayer:bayer_scale=5'
STATS = 'full'
ORIGEM = (1280, 720)
DURACAO = 43.1
POSICOES = (0.2, 0.6)
JANELA = 1.0

VF = f'fps={FPS},scale={LARGURA}:-2:flags=lanczos'

# Cada vídeo isola um regime de compressão diferente.
VIDEOS = {
    'cartão de título (estático)': (
        ['-f', 'lavfi', '-i', f'color=c=black:s={ORIGEM[0]}x{ORIGEM[1]}:r=30:d=46',
         '-vf', "drawtext=text='IRRIGATION PROJECT WITH':fontcolor=white:"
                "fontsize=64:x=(w-tw)/2:y=h/2-80,"
                "drawtext=text='AUTOMATIC MONITORING!':fontcolor=white:"
                "fontsize=64:x=(w-tw)/2:y=h/2+10"],
        '2500k'),
    'fundo parado, objeto se movendo': (
        ['-f', 'lavfi', '-i', f'color=c=0x203040:s={ORIGEM[0]}x{ORIGEM[1]}:r=30:d=46',
         '-f', 'lavfi', '-i', 'color=c=orange:s=120x120:d=46',
         '-filter_complex', "[0:v][1:v]overlay=x='(W-w)/2+400*sin(t)'"
                            ":y='(H-h)/2+200*cos(t)'"],
        '2500k'),
    'cena agitada': (
        ['-f', 'lavfi', '-i', f'testsrc2=s={ORIGEM[0]}x{ORIGEM[1]}:r=30:d=46'],
        '6000k'),
    # As cores e a semente são fixadas porque o `gradients` sorteia as duas
    # por padrão — sem isso o mesmo comando produz arquivos de tamanhos bem
    # diferentes a cada execução, e a medição deixa de ser reproduzível.
    'gradiente em movimento': (
        ['-f', 'lavfi', '-i',
         f'gradients=s={ORIGEM[0]}x{ORIGEM[1]}:r=30:d=46:speed=0.05'
         ':nb_colors=3:c0=0x1b2a6b:c1=0xd94f2b:c2=0x2bd9a8:seed=42'],
        '3000k'),
    'ruído (incompressível)': (
        ['-f', 'lavfi', '-i', f'color=c=gray:s={ORIGEM[0]}x{ORIGEM[1]}:r=30:d=46',
         '-vf', 'noise=alls=60:allf=t+u'],
        '9000k'),
}


def rodar(args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


def contar_quadros(caminho):
    saida = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_frames',
         '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', caminho],
        capture_output=True, text=True).stdout.strip()
    return int(saida)


def converter(origem, inicio, duracao, destino_base):
    """Devolve (bytes da janela, bytes do primeiro quadro, nº de quadros).

    As duas codificações compartilham a mesma paleta, que é o que o app faz —
    e o que torna a subtração entre elas significativa.
    """
    paleta = f'{destino_base}.png'
    gif = f'{destino_base}.gif'
    um_quadro = f'{destino_base}_1.gif'

    rodar(['ffmpeg', '-y', '-ss', f'{inicio:.3f}', '-t', f'{duracao:.3f}',
           '-i', origem, '-vf',
           f'{VF},palettegen=max_colors={CORES}:stats_mode={STATS}',
           '-frames:v', '1', paleta])

    base = ['ffmpeg', '-y', '-ss', f'{inicio:.3f}', '-t', f'{duracao:.3f}',
            '-i', origem, '-i', paleta, '-lavfi',
            f'[0:v]{VF}[v];[v][1:v]paletteuse=dither={DITHER}'
            ':diff_mode=rectangle', '-loop', '0', '-an']

    rodar(base + ['-f', 'gif', gif])
    rodar(base + ['-frames:v', '1', '-f', 'gif', um_quadro])

    return os.path.getsize(gif), os.path.getsize(um_quadro), contar_quadros(gif)


def main():
    for exe in ('ffmpeg', 'ffprobe'):
        if shutil.which(exe) is None:
            sys.exit(f'{exe} não encontrado no PATH.')

    altura = round(LARGURA * ORIGEM[1] / ORIGEM[0]) & ~1
    trabalho = tempfile.mkdtemp(prefix='precisao_')
    linhas = []

    print(f'saída {LARGURA}x{altura} · {FPS} FPS · {CORES} cores · '
          f'{DURACAO} s\n')

    try:
        for nome, (args, bitrate) in VIDEOS.items():
            fonte = os.path.join(trabalho, 'fonte.mp4')
            # -threads 1: o x264 multi-thread não é bit-a-bit determinístico,
            # e sem isso os tamanhos variam de uma execução para outra.
            rodar(['ffmpeg', '-y'] + args +
                  ['-c:v', 'libx264', '-b:v', bitrate, '-pix_fmt', 'yuv420p',
                   '-threads', '1', fonte])

            real, _, quadros = converter(fonte, 0, DURACAO,
                                         os.path.join(trabalho, 'inteiro'))

            amostras = []
            for i, fracao in enumerate(POSICOES):
                janela, primeiro, _ = converter(
                    fonte, DURACAO * fracao, JANELA,
                    os.path.join(trabalho, f'amostra{i}'))
                amostras.append((janela, primeiro))

            print(f'{nome:34} {real/1048576:7.2f} MB em {quadros} quadros')
            for i, (janela, primeiro) in enumerate(amostras):
                print(f'{"":34}   amostra {i+1}: janela {janela} B, '
                      f'1º quadro {primeiro} B')

            medicoes = ', '.join(f'_Medicao({j}, {p})' for j, p in amostras)
            linhas.append(f"  _Caso('{nome}', {real}, [{medicoes}]),")
    finally:
        shutil.rmtree(trabalho, ignore_errors=True)

    print('\nPara colar em test/size_estimator_medicoes_test.dart:\n')
    print('const _casos = <_Caso>[')
    for linha in linhas:
        print(linha)
    print('];')


if __name__ == '__main__':
    main()
