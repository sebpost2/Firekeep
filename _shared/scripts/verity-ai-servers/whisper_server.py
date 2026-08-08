# _shared/scripts/verity-ai-servers/whisper_server.py
# Minimal OpenAI-style STT server wrapping faster-whisper, for Verity's
# sttProvider = "WHISPER" / sttEndpoint = "http://127.0.0.1:9000/v1".
import tempfile

from fastapi import FastAPI, File, UploadFile
from faster_whisper import WhisperModel

# int8 quantization keeps this fast and light on CPU - plenty for short
# in-game voice clips; base.en downloads automatically on first use.
model = WhisperModel("base.en", device="cpu", compute_type="int8")

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    segments, _ = model.transcribe(tmp_path)
    text = "".join(segment.text for segment in segments)
    return {"text": text.strip()}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=9000)
