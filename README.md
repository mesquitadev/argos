<div align="center">

# Argos

**Um NVR que roda na sua casa.** Grava suas câmeras IP num servidor seu,
guarda o quanto o disco permitir e mostra tudo no navegador — do celular ao
desktop, sem nuvem e sem mensalidade.

</div>

---

Argos é o guardião de cem olhos da mitologia, que nunca dormia por completo:
sempre alguns olhos acordados enquanto os outros descansavam.

Ele tem duas metades. Um **gravador** que roda na sua máquina — um servidor de
homelab, um NAS, qualquer coisa com Docker — puxando RTSP e escrevendo em
disco em trechos, apagando os mais antigos conforme o espaço acaba, como um
DVR. E uma **aplicação web** servida pelo mesmo lugar, que mostra o ao vivo, a
linha do tempo e as gravações.

## Instalação

Copie `deploy/` para a máquina que vai gravar e suba:

```sh
cp .env.example .env    # credenciais de administrador e do banco
docker compose up -d
```

Abra o endereço da máquina na porta 8088, crie a senha, e em **Configurações ›
Câmeras** clique em **Procurar na rede**. Toda câmera ONVIF responde dizendo
fabricante e modelo — você adota, e a gravação começa em segundos. Nenhum
endereço IP precisa ser digitado.

## O que ele faz

**Várias câmeras**, cada uma com seu gravador e seu fluxo ao vivo, gerenciados
por um supervisor que lê o registro e mantém os processos certos no ar. O
mosaico se ajusta à quantidade — uma câmera ocupa a tela, quatro viram 2×2.

**Uma linha do tempo por dia**, que é o controle e não um enfeite: movimento em
âmbar acima, gravação em azul abaixo, cursor que anda com o vídeo. Clicar num
horário salta para aquele segundo, atravessando a fronteira entre arquivos sem
pausa — os trechos de cinco minutos ficam invisíveis.

**Detecção do que se moveu**, não só de que algo se moveu. Sombra de nuvem e
folha ao vento disparam movimento e não são nada; "pessoa às 11:23" vale o que
"movimento às 11:23" não vale. Roda por gatilho, nunca contínuo.

**Exportar um trecho**: marque início e fim na linha do tempo e baixe um MP4.
O corte é feito copiando, sem recodificar — sai em segundos, com a qualidade
que a câmera gravou.

**Retenção configurável**, com previsão antes de apagar. A tela diz o que a
política removeria — "40 trechos, 12 GB, até anteontem" — antes de você
confirmar.

**Usuários**, com papéis de administrador e de leitura. Sem isso, qualquer
pessoa na rede abre o endereço e assiste à sua casa.

## Compatibilidade

Câmeras **Dahua e compatíveis** — o que inclui Intelbras, que revende Dahua com
firmware próprio — mais **ONVIF genérico** para descoberta e RTSP. Desenvolvido
contra uma Intelbras VIP 3230 B.

## Requisitos

Docker na máquina que grava. Qualquer navegador para assistir; o Safari e o
iPhone tocam HLS nativamente, e os demais recebem a biblioteca junto com a
página — a casa não deve depender de internet para ver a própria câmera.

## Licença

MIT © Paulo Victor Mesquita
