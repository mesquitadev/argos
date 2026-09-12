package dev.mesquita.vigia.recorder;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Stream;

/**
 * Os arquivos gravados, e a conta de quanto ocupam.
 *
 * <p>Não há banco de dados aqui de propósito. O índice é o próprio disco: cada
 * segmento carrega a data e a hora no nome, e o diretório é a verdade. Um banco
 * paralelo abriria a porta para o pior defeito de um gravador — o índice dizer
 * que existe uma gravação que o disco já não tem, ou pior, apagar o arquivo e
 * deixar a linha do tempo mentindo. Com uma câmera, listar o diretório custa
 * milissegundos.
 */
public class SegmentStore {

    /** `2026-09-11/cam1_2026-09-11_14-30-00.mp4` — ordenável como texto. */
    public static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    public static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss");

    public record Segment(Path path, String cameraId, LocalDateTime startedAt, long bytes) {
        public String id() {
            return cameraId + "/" + startedAt.format(STAMP);
        }
    }

    private final Path root;

    public SegmentStore(Path root) {
        this.root = root;
    }

    public Path root() {
        return root;
    }

    /** Diretório do dia de uma câmera, criado sob demanda. */
    public Path dayDirectory(String cameraId, LocalDate day) throws IOException {
        Path directory = root.resolve(cameraId).resolve(day.format(DAY));
        Files.createDirectories(directory);
        return directory;
    }

    /** Todos os segmentos, do mais antigo para o mais novo. */
    public List<Segment> all() throws IOException {
        if (!Files.exists(root)) return List.of();
        try (Stream<Path> walk = Files.walk(root)) {
            return walk.filter(path -> path.toString().endsWith(".mp4"))
                       .map(this::describe)
                       .filter(Objects::nonNull)
                       .sorted(Comparator.comparing(Segment::startedAt))
                       .toList();
        }
    }

    /** Segmentos de uma câmera dentro de um intervalo — a busca da linha do tempo. */
    public List<Segment> between(String cameraId, LocalDateTime from, LocalDateTime to) throws IOException {
        return all().stream()
            .filter(segment -> segment.cameraId().equals(cameraId))
            .filter(segment -> !segment.startedAt().isBefore(from) && !segment.startedAt().isAfter(to))
            .toList();
    }

    public long totalBytes() throws IOException {
        return all().stream().mapToLong(Segment::bytes).sum();
    }

    /**
     * Lê a identidade do segmento do próprio caminho. Um arquivo com nome fora
     * do padrão é ignorado em vez de derrubar a listagem: no diretório de
     * gravação pode cair qualquer coisa, e um `.DS_Store` não pode quebrar o
     * gravador.
     */
    private Segment describe(Path path) {
        try {
            String name = path.getFileName().toString().replace(".mp4", "");
            int separator = name.indexOf('_');
            if (separator < 0) return null;

            String cameraId = name.substring(0, separator);
            LocalDateTime startedAt = LocalDateTime.parse(name.substring(separator + 1), STAMP);
            BasicFileAttributes attributes = Files.readAttributes(path, BasicFileAttributes.class);
            return new Segment(path, cameraId, startedAt, attributes.size());
        } catch (Exception ignored) {
            return null;
        }
    }
}
