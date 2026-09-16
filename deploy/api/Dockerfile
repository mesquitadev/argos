# Imagem da API: Python com ffmpeg ao lado.
#
# Construída em vez de instalar pacote no arranque — instalar a cada restart
# depende da internet no pior momento, e uma falha de rede deixaria o serviço
# sem subir. Aqui a imagem é fixa e o container sobe mesmo offline.
FROM python:3.12-alpine

# ffmpeg para exportar trechos; tzdata porque, sem ele, TZ cai para UTC em
# silêncio e os horários no nome dos arquivos deixam de bater.
RUN apk add --no-cache ffmpeg tzdata

WORKDIR /api
COPY auth.py server.py manage.py retention.py /api/

# Sem escrever .pyc numa pasta montada como somente leitura, e com a saída sem
# buffer para o log aparecer na hora.
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

EXPOSE 8090
CMD ["python3", "/api/server.py"]
