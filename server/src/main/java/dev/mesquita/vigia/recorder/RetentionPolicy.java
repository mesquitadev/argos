package dev.mesquita.vigia.recorder;

import java.io.IOException;
import java.nio.file.*;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Apaga o passado para caber o presente, como faz um DVR.
 *
 * <p>Duas regras agem juntas, e a mais restritiva vence:
 *
 * <ul>
 *   <li><b>Espaço</b> — o gravador nunca passa do teto configurado, e sempre
 *       deixa uma folga livre no volume. Sem a folga, o disco enche e quem
 *       para de gravar é o próprio sistema, no pior momento possível.
 *   <li><b>Idade</b> — nada mais velho que o limite de dias é mantido, mesmo
 *       que haja espaço sobrando. Guardar imagem além do necessário é risco
 *       sem contrapartida.
 * </ul>
 *
 * <p>A ordem importa: apaga-se sempre o segmento mais antigo primeiro, um a
 * um, conferindo o espaço a cada remoção. Apagar um dia inteiro de uma vez
 * seria mais rápido e faria a linha do tempo saltar sem necessidade.
 */
public class RetentionPolicy {

    public record Limits(long maxBytes, int maxDays, long minimumFreeBytes) {}

    public record Result(int removedSegments, long freedBytes, String reason) {}

    private final SegmentStore store;
    private final Limits limits;

    public RetentionPolicy(SegmentStore store, Limits limits) {
        this.store = store;
        this.limits = limits;
    }

    public Result apply() throws IOException {
        List<SegmentStore.Segment> segments = store.all();
        if (segments.isEmpty()) return new Result(0, 0, "nada gravado");

        long used = segments.stream().mapToLong(SegmentStore.Segment::bytes).sum();
        long free = freeSpace();
        LocalDateTime oldestAllowed = LocalDateTime.now().minusDays(limits.maxDays());

        int removed = 0;
        long freed = 0;
        String reason = "dentro dos limites";

        for (SegmentStore.Segment segment : segments) {
            boolean tooOld = segment.startedAt().isBefore(oldestAllowed);
            boolean overQuota = used > limits.maxBytes();
            boolean diskTight = free < limits.minimumFreeBytes();

            if (!tooOld && !overQuota && !diskTight) break;

            reason = tooOld ? "mais antigo que %d dias".formatted(limits.maxDays())
                   : diskTight ? "pouco espaço livre no volume"
                   : "acima do teto de espaço";

            try {
                Files.deleteIfExists(segment.path());
                used -= segment.bytes();
                free += segment.bytes();
                freed += segment.bytes();
                removed++;
            } catch (IOException failure) {
                // Um arquivo em uso pelo próprio ffmpeg não pode derrubar a
                // limpeza: passa para o próximo e tenta de novo no próximo ciclo.
                continue;
            }
        }

        removeEmptyDayDirectories();
        return new Result(removed, freed, reason);
    }

    /** Espaço livre real do volume onde a gravação está. */
    private long freeSpace() throws IOException {
        return Files.getFileStore(store.root()).getUsableSpace();
    }

    /** Pastas de dias já esvaziadas viram ruído na navegação. */
    private void removeEmptyDayDirectories() throws IOException {
        if (!Files.exists(store.root())) return;
        try (var walk = Files.walk(store.root(), 2)) {
            walk.filter(Files::isDirectory)
                .filter(path -> !path.equals(store.root()))
                .sorted((a, b) -> b.getNameCount() - a.getNameCount())
                .forEach(path -> {
                    try (var entries = Files.list(path)) {
                        if (entries.findAny().isEmpty()) Files.deleteIfExists(path);
                    } catch (IOException ignored) {
                        // Diretório que sumiu no meio do caminho não é problema.
                    }
                });
        }
    }
}
