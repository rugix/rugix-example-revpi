FROM docker.io/library/python:3.12-slim-bookworm

WORKDIR /app
COPY requirements.txt /app/
RUN mkdir -p /etc/revpi && pip install --no-cache-dir -r /app/requirements.txt
COPY app/ /app/

CMD ["python", "/app/app.py"]
