# Use the official Playwright image for Python
# This keeps us safe from missing browser dependencies
FROM mcr.microsoft.com/playwright/python:v1.40.0-focal

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install gunicorn

# Install Playwright browsers (Chromium is usually enough, but install all to be safe)
RUN playwright install chromium
RUN playwright install-deps

# Copy the rest of the application
COPY . .

# Expose the port
EXPOSE 5000

# Run the application using Gunicorn
# 1 worker is usually enough for this watcher logic, but 2 is safe
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "--timeout", "120", "api_server:app"]
