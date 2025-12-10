from fastapi import FastAPI

app = FastAPI()
notes = []

@app.get("/notes")
def get_notes():
    return notes

@app.post("/notes")
def add_note(note: str):
    notes.append(note)
    return {"status": "ok", "notes": notes}
