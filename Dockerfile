FROM python:3.12-slim
WORKDIR /app

# Install dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY . .

# Default active profile – override with HERMES_PROFILE env var
ENV HERMES_PROFILE=default

CMD ["python", "-m", "hermes"]
