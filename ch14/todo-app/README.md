# Simple TODO Application

A lightweight TODO application that allows you to create, view, update, and delete tasks.

## Features

- Create new tasks with title and description
- Mark tasks as complete/incomplete
- Delete tasks
- View all tasks
- In-memory storage (no database required)

## Technical Details

- Built with Python 3.13 and Flask 3.x
- Single-page application with RESTful API
- Containerized with Docker, served by gunicorn

## Running Locally

### Without Docker

1. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

2. Run the application:
   ```
   python app.py
   ```

3. Access the application at http://localhost:5000

### With Docker

1. Build the Docker image:
   ```
   docker build -t todo-app .
   ```

2. Run the container:
   ```
   docker run -p 5000:5000 todo-app
   ```

3. Access the application at http://localhost:5000

## API Endpoints

- `GET /api/tasks` - Get all tasks
- `POST /api/tasks` - Create a new task
- `GET /api/tasks/<task_id>` - Get a specific task
- `PUT /api/tasks/<task_id>` - Update a task
- `DELETE /api/tasks/<task_id>` - Delete a task

## Docker Best Practices Used

- Uses a slim base image to reduce size
- Pins the base image tag so builds are reproducible
- Creates a non-root user for security
- Sets appropriate environment variables
- Installs dependencies before copying application code, so the dependency layer stays cached
- Properly exposes the application port
- Uses gunicorn for production deployment

## Version notes

- The base image moved from `python:3.9-slim` to `python:3.13-slim`. Python 3.9
  is end-of-life and no longer receives security updates.
- Flask, Werkzeug, and gunicorn were updated from 2.0.1 / 2.0.1 / 20.1.0 to
  3.1.3 / 3.1.8 / 26.2.0. The old pins do not install or run correctly on
  current Python.
- `app.py` runs with `debug=True` under `python app.py`, which is fine locally
  but must never be used in a deployed environment. The container image uses
  gunicorn instead, so `debug` is not in play there.
