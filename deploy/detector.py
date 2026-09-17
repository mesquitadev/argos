"""Diz o que se moveu, não só que algo se moveu.

Roda por gatilho, nunca contínuo. A câmera já sabe quando algo mexeu — analisar
todo quadro de todas as câmeras gastaria a máquina inteira para reconfirmar o
que o sensor de movimento já disse de graça. Ao receber um evento, pega um
quadro do fluxo ao vivo, identifica o que há nele e anexa o resultado.

O ganho é cortar alarme falso: sombra de nuvem, folha ao vento e reflexo de
farol disparam movimento e não são nada. "Pessoa às 11:23" vale o que
"movimento às 11:23" não vale.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

MODELO = os.environ.get("MODELO", "/modelo/yolo.onnx")
REGISTRO = os.environ.get("CAMERAS_FILE", "/config-cameras/cameras.json")
HLS = Path(os.environ.get("HLS_DIR", "/hls"))
LADO = 640
CONFIANCA = float(os.environ.get("CONFIANCA", "0.35"))
# Não adianta analisar duas vezes o mesmo episódio: a câmera dispara início e
# fim a cada oscilação, e a cena não muda em segundos.
INTERVALO_MINIMO = float(os.environ.get("INTERVALO_MINIMO", "20"))

# As classes do COCO que importam numa cena doméstica. O resto — mala, vaso,
# semáforo — só geraria ruído.
INTERESSE = {
    0: "pessoa", 1: "bicicleta", 2: "carro", 3: "moto",
    5: "ônibus", 7: "caminhão", 15: "gato", 16: "cachorro",
}


def log(mensagem: str) -> None:
    print(f"[detector] {mensagem}", flush=True)


def carregar_cameras() -> list[dict]:
    try:
        with open(REGISTRO) as handle:
            return [c for c in json.load(handle) if c.get("enabled", True)]
    except (OSError, ValueError):
        return []


def preparar(imagem):
    """Redimensiona mantendo proporção e completa com cinza.

    Esticar distorceria as formas que o modelo aprendeu; a borda cinza preserva
    a geometria e o modelo aprende a ignorá-la.
    """
    altura, largura = imagem.shape[:2]
    escala = LADO / max(altura, largura)
    nova = cv2.resize(imagem, (int(largura * escala), int(altura * escala)))
    tela = np.full((LADO, LADO, 3), 114, dtype=np.uint8)
    tela[: nova.shape[0], : nova.shape[1]] = nova
    entrada = cv2.cvtColor(tela, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    return np.transpose(entrada, (2, 0, 1))[None], escala


class Detector:
    def __init__(self) -> None:
        # Um núcleo só: o resto da máquina está gravando, e detecção que
        # atropela a gravação troca uma conveniência por uma função essencial.
        opcoes = ort.SessionOptions()
        opcoes.intra_op_num_threads = int(os.environ.get("THREADS", "1"))
        self.sessao = ort.InferenceSession(MODELO, opcoes, providers=["CPUExecutionProvider"])
        self.entrada = self.sessao.get_inputs()[0].name
        log(f"modelo carregado: {MODELO}")

    def detectar(self, imagem) -> list[dict]:
        tensor, escala = preparar(imagem)
        predicoes = np.squeeze(self.sessao.run(None, {self.entrada: tensor})[0]).T

        pontuacoes = predicoes[:, 4:]
        classes = pontuacoes.argmax(axis=1)
        confiancas = pontuacoes.max(axis=1)

        caixas, scores, rotulos = [], [], []
        for i in np.where(confiancas >= CONFIANCA)[0]:
            classe = int(classes[i])
            if classe not in INTERESSE:
                continue
            cx, cy, w, h = predicoes[i, :4] / escala
            caixas.append([int(cx - w / 2), int(cy - h / 2), int(w), int(h)])
            scores.append(float(confiancas[i]))
            rotulos.append(INTERESSE[classe])

        if not caixas:
            return []

        # O YOLO emite dezenas de caixas sobrepostas para o mesmo objeto. Sem
        # colapsá-las, dois carros parados viram quarenta — e a contagem, que é
        # o que dá sentido ao alerta, deixa de significar qualquer coisa.
        # Medido nesta câmera: 3228 detecções viraram 311, que é o número real.
        indices = cv2.dnn.NMSBoxes(caixas, scores, CONFIANCA, 0.45)
        if len(indices) == 0:
            return []

        altura, largura = imagem.shape[:2]
        return [
            {
                "o_que": rotulos[int(i)],
                "confianca": round(scores[int(i)], 3),
                # Normalizado: a caixa serve em qualquer tamanho de tela sem o
                # cliente precisar saber a resolução do quadro.
                "caixa": [round(caixas[int(i)][0] / largura, 4),
                          round(caixas[int(i)][1] / altura, 4),
                          round(caixas[int(i)][2] / largura, 4),
                          round(caixas[int(i)][3] / altura, 4)],
            }
            for i in np.array(indices).flatten()
        ]


def capturar(camera_id: str) -> "np.ndarray | None":
    """Um quadro do fluxo ao vivo.

    Lê o HLS que já existe em vez de abrir uma segunda conexão RTSP com a
    câmera: algumas limitam o número de fluxos simultâneos, e gastar um deles
    aqui poderia derrubar a gravação.
    """
    playlist = HLS / camera_id / f"{camera_id}.m3u8"
    if not playlist.exists():
        return None
    destino = f"/tmp/{camera_id}.jpg"
    resultado = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-i", str(playlist), "-frames:v", "1", "-q:v", "3", destino],
        capture_output=True, timeout=30,
    )
    if resultado.returncode != 0:
        return None
    return cv2.imread(destino)


def registrar(camera_id: str, evento: dict, achados: list[dict]) -> None:
    linha = {
        "camera": camera_id,
        "at": evento["at"],
        "gatilho": evento.get("code", "VideoMotion"),
        "objetos": achados,
    }
    arquivo = HLS / camera_id / "detections.jsonl"
    with arquivo.open("a") as handle:
        handle.write(json.dumps(linha, ensure_ascii=False) + "\n")

    resumo = ", ".join(f"{a['o_que']} {a['confianca']:.2f}" for a in achados) or "nada reconhecido"
    log(f"{camera_id} {evento['at']}: {resumo}")


def ultimos_inicios(camera_id: str, desde: str) -> list[dict]:
    """Eventos de início de movimento ainda não analisados."""
    arquivo = HLS / camera_id / "events.jsonl"
    if not arquivo.exists():
        return []
    novos = []
    for linha in arquivo.read_text(errors="ignore").splitlines()[-200:]:
        try:
            evento = json.loads(linha)
        except ValueError:
            continue
        if evento.get("action") == "Start" and evento.get("at", "") > desde:
            novos.append(evento)
    return novos


def main() -> None:
    detector = Detector()
    marcas: dict[str, str] = {}
    ultima_analise: dict[str, float] = {}

    while True:
        for camera in carregar_cameras():
            ident = camera["id"]
            (HLS / ident).mkdir(parents=True, exist_ok=True)

            # Na primeira volta só marca onde estamos: analisar o histórico
            # inteiro ao subir travaria a máquina por minutos sem utilidade.
            if ident not in marcas:
                eventos = ultimos_inicios(ident, "")
                marcas[ident] = eventos[-1]["at"] if eventos else ""
                continue

            novos = ultimos_inicios(ident, marcas[ident])
            if not novos:
                continue
            marcas[ident] = novos[-1]["at"]

            if time.monotonic() - ultima_analise.get(ident, 0) < INTERVALO_MINIMO:
                continue
            ultima_analise[ident] = time.monotonic()

            try:
                imagem = capturar(ident)
                if imagem is None:
                    log(f"{ident}: não consegui capturar quadro")
                    continue
                registrar(ident, novos[-1], detector.detectar(imagem))
            except Exception as erro:      # noqa: BLE001
                log(f"{ident}: falhou — {erro}")

        time.sleep(3)


if __name__ == "__main__":
    main()
