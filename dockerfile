# Build stage
FROM python:3.6-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt gunicorn

# Runtime stage
FROM python:3.6-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY app.py .
ENV PATH=/root/.local/bin:$PATH
EXPOSE 80
CMD ["gunicorn", "--bind", "0.0.0.0:80", "app:app"]
