from fastapi import FastAPI

app = FastAPI(title="DevLens")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "DevLens",
        "version": "0.1.0"
    }
