package dev.mesquita.vigia.recorder;

import org.junit.jupiter.api.*;
import java.io.IOException;
import java.nio.file.*;
import java.time.LocalDateTime;
import static org.junit.jupiter.api.Assertions.*;

class RetentionPolicyTest {

    Path root;
    SegmentStore store;

    @BeforeEach
    void setUp() throws IOException {
        root = Files.createTempDirectory("vigia-test");
        store = new SegmentStore(root);
    }

    @AfterEach
    void tearDown() throws IOException {
        try (var walk = Files.walk(root)) {
            walk.sorted((a, b) -> b.getNameCount() - a.getNameCount())
                .forEach(p -> { try { Files.deleteIfExists(p); } catch (IOException ignored) {} });
        }
    }

    /** Cria um segmento com data e tamanho controlados. */
    private Path segment(String camera, LocalDateTime when, int sizeKb) throws IOException {
        Path dir = store.dayDirectory(camera, when.toLocalDate());
        Path file = dir.resolve(camera + "_" + when.format(SegmentStore.STAMP) + ".mp4");
        Files.write(file, new byte[sizeKb * 1024]);
        return file;
    }

    @Test
    void apagaOMaisAntigoPrimeiroAoEstourarOEspaco() throws IOException {
        var now = LocalDateTime.now();
        Path oldest = segment("cam1", now.minusHours(5), 100);
        Path middle = segment("cam1", now.minusHours(3), 100);
        Path newest = segment("cam1", now.minusHours(1), 100);

        // Teto de 250 KB: sobra espaço para dois segmentos, não três.
        var policy = new RetentionPolicy(store, new RetentionPolicy.Limits(250 * 1024, 365, 0));
        var result = policy.apply();

        assertEquals(1, result.removedSegments());
        assertFalse(Files.exists(oldest), "o mais antigo sai primeiro");
        assertTrue(Files.exists(middle), "o do meio permanece");
        assertTrue(Files.exists(newest), "o mais recente nunca é o primeiro a sair");
    }

    @Test
    void apagaPorIdadeMesmoComEspacoSobrando() throws IOException {
        var now = LocalDateTime.now();
        Path old = segment("cam1", now.minusDays(40), 10);
        Path recent = segment("cam1", now.minusDays(2), 10);

        // Espaço de sobra, mas 30 dias de limite.
        var policy = new RetentionPolicy(store, new RetentionPolicy.Limits(Long.MAX_VALUE, 30, 0));
        var result = policy.apply();

        assertEquals(1, result.removedSegments());
        assertFalse(Files.exists(old));
        assertTrue(Files.exists(recent));
        assertTrue(result.reason().contains("30 dias"));
    }

    @Test
    void naoApagaNadaQuandoEstaDentroDosLimites() throws IOException {
        var now = LocalDateTime.now();
        segment("cam1", now.minusHours(2), 10);
        segment("cam1", now.minusHours(1), 10);

        var policy = new RetentionPolicy(store, new RetentionPolicy.Limits(Long.MAX_VALUE, 365, 0));
        var result = policy.apply();

        assertEquals(0, result.removedSegments(), "sem motivo, não se apaga gravação");
        assertEquals(2, store.all().size());
    }

    @Test
    void removePastasDeDiaVaziasDepoisDaLimpeza() throws IOException {
        var now = LocalDateTime.now();
        segment("cam1", now.minusDays(40), 10);
        Path emptyDay = root.resolve("cam1").resolve(now.minusDays(40).toLocalDate()
            .format(SegmentStore.DAY));
        assertTrue(Files.exists(emptyDay));

        new RetentionPolicy(store, new RetentionPolicy.Limits(Long.MAX_VALUE, 30, 0)).apply();
        assertFalse(Files.exists(emptyDay), "pasta de dia vazia não fica para trás");
    }

    @Test
    void indiceLeDataEHoraDoNomeDoArquivo() throws IOException {
        var when = LocalDateTime.of(2026, 9, 11, 14, 30, 0);
        segment("cam1", when, 10);

        var all = store.all();
        assertEquals(1, all.size());
        assertEquals("cam1", all.get(0).cameraId());
        assertEquals(when, all.get(0).startedAt());
    }

    /** Arquivo estranho no diretório não pode derrubar a listagem. */
    @Test
    void ignoraArquivoComNomeForaDoPadrao() throws IOException {
        segment("cam1", LocalDateTime.now(), 10);
        Files.write(root.resolve("cam1").resolve(".DS_Store"), new byte[10]);
        Files.write(root.resolve("cam1").resolve("qualquer-coisa.mp4"), new byte[10]);

        assertEquals(1, store.all().size(), "só o segmento válido entra no índice");
    }
}
