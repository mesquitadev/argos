package dev.mesquita.vigia.recorder;

import java.io.IOException;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Mantém um processo de gravação vivo para uma câmera.
 *
 * <p>O trabalho pesado é do ffmpeg, e de propósito: ele já sabe falar RTSP,
 * reconectar, e cortar o fluxo em arquivos sem recodificar. A decisão central
 * aqui é <b>copiar os pacotes em vez de recodificar</b> — a câmera já entrega
 * H.264 ou H.265 prontos, e transcodificar gastaria CPU o dia inteiro para
 * produzir uma imagem pior do que a que chegou.
 *
 * <p>Consequência disso: o corte dos segmentos cai no quadro-chave mais próximo,
 * então um segmento de 10 minutos pode ter 10 minutos e alguns segundos. Para
 * um gravador isso é irrelevante e o índice usa o horário real de início.
 */
public class CameraRecorder {

    public record Camera(String id, String rtspUrl, int segmentSeconds) {}

    public interface Log {
        void line(String message);
    }

    private final Camera camera;
    private final SegmentStore store;
    private final Log log;
    private final AtomicReference<Process> current = new AtomicReference<>();
    private volatile boolean running;

    public CameraRecorder(Camera camera, SegmentStore store, Log log) {
        this.camera = camera;
        this.store = store;
        this.log = log;
    }

    public boolean isRunning() {
        Process process = current.get();
        return running && process != null && process.isAlive();
    }

    /**
     * Começa a gravar e se mantém gravando. Se o ffmpeg morrer — queda de rede,
     * câmera reiniciando, cabo solto — o laço espera e tenta de novo, porque um
     * gravador que desiste na primeira falha não é um gravador.
     */
    public void start() {
        running = true;
        Thread.ofVirtual().name("recorder-" + camera.id()).start(() -> {
            int failures = 0;
            while (running) {
                try {
                    int exit = runOnce();
                    if (!running) break;
                    failures = exit == 0 ? 0 : failures + 1;
                    log.line("gravação encerrou (código %d), reconectando".formatted(exit));
                } catch (Exception failure) {
                    failures++;
                    log.line("falha ao gravar: " + failure.getMessage());
                }
                // Espera progressiva até 30s: insistir a cada segundo numa
                // câmera desligada só enche o log e a rede.
                long waitSeconds = Math.min(30, 1L << Math.min(failures, 5));
                try {
                    Thread.sleep(waitSeconds * 1000);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        });
    }

    public void stop() {
        running = false;
        Process process = current.get();
        if (process != null && process.isAlive()) {
            // O ffmpeg fecha o arquivo corrente ao receber SIGTERM; matar direto
            // deixaria o último segmento truncado e sem índice de moov.
            process.destroy();
            try {
                if (!process.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)) process.destroyForcibly();
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private int runOnce() throws IOException, InterruptedException {
        Path directory = store.dayDirectory(camera.id(), LocalDate.now());
        // O padrão de nome usa strftime do próprio ffmpeg, então cada segmento
        // nasce com o horário real em que começou — sem depender de nós.
        String pattern = directory.resolve(camera.id() + "_%Y-%m-%d_%H-%M-%S.mp4").toString();

        List<String> command = new ArrayList<>(List.of(
            "ffmpeg", "-hide_banner", "-loglevel", "warning",
            // TCP em vez de UDP: em rede doméstica com Wi-Fi, UDP perde pacote
            // e o vídeo fica com blocos quebrados que ninguém consegue usar.
            "-rtsp_transport", "tcp",
            "-timeout", "10000000",
            "-i", camera.rtspUrl(),
            "-c", "copy",
            "-f", "segment",
            "-segment_time", String.valueOf(camera.segmentSeconds()),
            // Cortar no quadro-chave é o que permite reproduzir um segmento
            // isolado sem depender do anterior.
            "-reset_timestamps", "1",
            "-strftime", "1",
            // MP4 fragmentado: se faltar energia no meio, o arquivo continua
            // reproduzível até o ponto em que parou. Um MP4 comum sem o índice
            // final seria lixo.
            "-movflags", "+frag_keyframe+empty_moov+default_base_moof",
            pattern
        ));

        ProcessBuilder builder = new ProcessBuilder(command);
        builder.redirectErrorStream(true);
        Process process = builder.start();
        current.set(process);

        try (var reader = process.inputReader()) {
            String line;
            while ((line = reader.readLine()) != null) log.line(line);
        }
        return process.waitFor();
    }
}
