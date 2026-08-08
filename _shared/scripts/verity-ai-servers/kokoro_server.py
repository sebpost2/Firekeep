# Minimal OpenAI-style TTS server wrapping kokoro-onnx, for Verity's
# ttsProvider = "KOKORO" / ttsEndpoint = "http://127.0.0.1:8880/v1".
import io
import os
import wave

from fastapi import FastAPI, Response
from pydantic import BaseModel
from kokoro_onnx import Kokoro

MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
kokoro = Kokoro(
    os.path.join(MODEL_DIR, "kokoro-v1.0.onnx"),
    os.path.join(MODEL_DIR, "voices-v1.0.bin"),
)

app = FastAPI()


class SpeechRequest(BaseModel):
    input: str
    voice: str = "am_fenrir"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/audio/speech")
def speech(req: SpeechRequest):
    samples, sample_rate = kokoro.create(req.input, voice=req.voice)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        pcm16 = (samples * 32767).astype("int16")
        wf.writeframes(pcm16.tobytes())
    return Response(content=buf.getvalue(), media_type="audio/wav")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8880)
