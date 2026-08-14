import json
import os
import io
import asyncio
import sqlite3
import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry
from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, UploadFile, File, Header
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
import pypdf
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from tavily import TavilyClient

# 1. Load Environment Variables
load_dotenv(override=True)

DEFAULT_GROQ_KEY = ""
DEFAULT_TAVILY_KEY = ""

def get_groq_key():
    k = os.environ.get("GROQ_API_KEY", "").strip()
    return k if k else DEFAULT_GROQ_KEY

def get_tavily_key():
    k = os.environ.get("TAVILY_API_KEY", "").strip()
    return k if k else DEFAULT_TAVILY_KEY

# Configure HTTP Session with Retries
http_session = requests.Session()
retries = Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504])
http_session.mount("https://", HTTPAdapter(max_retries=retries))

MODELS = {
    "flash": "llama-3.1-8b-instant",
    "pro": "llama-3.3-70b-versatile"
}

SYSTEM_PROMPT = """You are Dora, a helpful, advanced, highly intelligent AI assistant.

ATTACHMENT & DOCUMENT ANALYSIS INSTRUCTIONS:
If the user's input contains a block starting with '--- BEGIN ATTACHED FILE CONTEXT ---' or '[Attached File: ...]', you MUST:
1. Thoroughly analyze and extract key insights, data, tables, financial summaries, or code explanations from the attached file context provided.
2. NEVER state that you cannot access files or read attachments. You HAVE been provided the full extracted text content of the attached document!
3. Provide a clear, beautifully structured markdown report (with headers, key takeaways, and breakdown) addressing the user's prompt.

GENERATIVE UI INSTRUCTIONS:
You can render rich, interactive UI components directly in the chat interface by appending one of the following JSON blocks at the very end of your response when relevant:

1. WEATHER CARD (if user asks about weather or forecast):
[UI:WEATHER_CARD]{"location": "City, Country", "temp": "22°C", "condition": "Sunny / Clear"}[/UI:WEATHER_CARD]

2. TASK CHECKLIST CARD (if user asks for a step-by-step plan, recipe, todo list, or checklist):
[UI:TASK_CARD]{"title": "Action Plan Title", "tasks": ["Task item 1", "Task item 2", "Task item 3"]}[/UI:TASK_CARD]

3. CHART CARD (if user asks for numerical data comparisons or statistics):
[UI:CHART_CARD]{"title": "Data Comparison", "labels": ["Category A", "Category B", "Category C"], "values": [35, 55, 80]}[/UI:CHART_CARD]

RULE: Write clear, markdown-formatted responses with headers, bullet points, and code blocks where appropriate. Only include UI cards when explicitly requested or highly relevant.
"""

limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])
app = FastAPI(title="Dora AI Backend API")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

def verify_google_identity(authorization: str = None):
    if not authorization:
        return None
    try:
        clean_token = authorization.replace("Bearer ", "").strip()
        id_info = id_token.verify_oauth2_token(clean_token, google_requests.Request())
        return id_info
    except Exception as e:
        print(f"[AUTH VERIFICATION INFO] Token validation result: {e}")
        return None

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def needs_web_search(message: str, deep_research: bool) -> bool:
    if deep_research:
        return True
    search_keywords = ["search", "latest", "news", "today", "weather", "current", "stock price", "who is", "what happened"]
    return any(kw in message.lower() for kw in search_keywords)

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default_user"
    model: str = "flash"
    deep_research: bool = False

class ModifyRequest(BaseModel):
    text: str
    instruction: str

@app.post("/chat/modify")
def modify_text(req: ModifyRequest):
    prompt = f"Rewrite the following text to make it {req.instruction}:\n\n{req.text}"
    headers = {
        "Authorization": f"Bearer {get_groq_key()}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3
    }
    try:
        res = http_session.post("https://api.groq.com/openai/v1/chat/completions", headers=headers, json=payload, timeout=20)
        data = res.json()
        return {"modified_text": data["choices"][0]["message"]["content"]}
    except Exception as e:
        return {"modified_text": f"[Error modifying text: {str(e)}]"}

def stream_groq_sync(messages: list, model_name: str):
    headers = {
        "Authorization": f"Bearer {get_groq_key()}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": model_name,
        "messages": messages,
        "temperature": 0.2,
        "stream": True
    }
    res = http_session.post("https://api.groq.com/openai/v1/chat/completions", headers=headers, json=payload, stream=True, timeout=30)
    for chunk in res.iter_lines():
        if chunk:
            line = chunk.decode("utf-8")
            if line.startswith("data: "):
                data_str = line[6:].strip()
                if data_str == "[DONE]":
                    break
                try:
                    data = json.loads(data_str)
                    delta = data["choices"][0]["delta"].get("content", "")
                    if delta:
                        yield delta
                except Exception:
                    pass

async def generate_ai_stream(message: str, session_id: str, model_key: str = "flash", deep_research: bool = False):
    groq_model = MODELS.get(model_key, MODELS["flash"])
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    if needs_web_search(message, deep_research):
        tavily_k = get_tavily_key()
        if tavily_k:
            yield f"data: {json.dumps({'content': '[Searching Google & Tavily Web...]\n\n'})}\n\n"
            try:
                tavily = TavilyClient(api_key=tavily_k)
                search_res = tavily.search(message, max_results=3)
                search_context = "\n\n--- WEB SEARCH RESULTS ---\n"
                for res in search_res.get("results", []):
                    search_context += f"Source: {res.get('title')} ({res.get('url')})\nContent: {res.get('content')}\n\n"
                messages.append({"role": "system", "content": f"The following live web search results were found:\n{search_context}\nSynthesize a complete answer."})
            except Exception as e:
                print(f"[SEARCH ERROR] {e}")

    messages.append({"role": "user", "content": message})

    try:
        for token in stream_groq_sync(messages, groq_model):
            yield f"data: {json.dumps({'content': token})}\n\n"
            await asyncio.sleep(0.005)
    except Exception as e:
        yield f"data: {json.dumps({'content': f'\n\n[AI Error: {str(e)}]'})}\n\n"

@app.post("/chat")
async def chat(request: ChatRequest):
    return StreamingResponse(generate_ai_stream(request.message, request.session_id, request.model, request.deep_research), media_type="text/event-stream")

@app.websocket("/ws/chat/{session_id}")
async def websocket_chat(websocket: WebSocket, session_id: str):
    await websocket.accept()
    try:
        while True:
            data_str = await websocket.receive_text()
            try:
                data = json.loads(data_str)
                user_message = data.get("message", "")
                model_key = data.get("model", "flash")
                deep_research = data.get("deep_research", False)
            except Exception:
                user_message = data_str
                model_key = "flash"
                deep_research = False

            if not user_message.strip():
                continue

            await websocket.send_json({"type": "start"})

            groq_model = MODELS.get(model_key, MODELS["flash"])
            messages = [{"role": "system", "content": SYSTEM_PROMPT}]

            if needs_web_search(user_message, deep_research):
                tavily_k = get_tavily_key()
                if tavily_k:
                    await websocket.send_json({"type": "tool_start", "tool": "Google Search & Tavily"})
                    try:
                        tavily = TavilyClient(api_key=tavily_k)
                        search_res = tavily.search(user_message, max_results=3)
                        sources = []
                        search_context = "\n\n--- WEB SEARCH RESULTS ---\n"
                        for res in search_res.get("results", []):
                            search_context += f"Source: {res.get('title')} ({res.get('url')})\nContent: {res.get('content')}\n\n"
                            sources.append({"title": res.get("title", "Web Source"), "url": res.get("url", "")})
                        await websocket.send_json({"type": "tool_end", "sources": sources})
                        messages.append({"role": "system", "content": f"The following live web search results were found:\n{search_context}\nSynthesize a complete answer."})
                    except Exception as e:
                        print(f"[SEARCH ERROR] {e}")

            messages.append({"role": "user", "content": user_message})

            try:
                for token in stream_groq_sync(messages, groq_model):
                    await websocket.send_json({"type": "token", "content": token})
                    await asyncio.sleep(0.005)
            except Exception as e:
                print(f"[STREAM ERROR] {e}")
                await websocket.send_json({"type": "token", "content": f"\n\n[AI response error: {str(e)}]"})

            await websocket.send_json({"type": "done"})

    except WebSocketDisconnect:
        print(f"WS Disconnected: session {session_id}")
    except Exception as e:
        print(f"WS error: {e}")
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass

@app.post("/api/upload-document")
@limiter.limit("20/minute")
async def upload_document(request: Request, file: UploadFile = File(...)):
    try:
        filename = file.filename or "uploaded_file"
        raw_bytes = await file.read()
        extracted_text = ""
        
        if filename.lower().endswith(".pdf"):
            pdf_reader = pypdf.PdfReader(io.BytesIO(raw_bytes))
            for page in pdf_reader.pages:
                text = page.extract_text()
                if text:
                    extracted_text += text + "\n"
        elif filename.lower().endswith((".txt", ".csv", ".json", ".py", ".dart", ".js", ".html", ".css", ".md")):
            extracted_text = raw_bytes.decode("utf-8", errors="ignore")
        else:
            extracted_text = raw_bytes.decode("utf-8", errors="ignore")

        if not extracted_text.strip():
            extracted_text = f"[Binary / Unparsed file: {filename} ({len(raw_bytes)} bytes)]"

        return {
            "status": "success",
            "filename": filename,
            "char_count": len(extracted_text),
            "text": extracted_text[:15000]
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

DB_PATH = "user_chats.db"

def init_sqlite_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            title TEXT NOT NULL,
            messages_json TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_user_email ON user_chats (user_email);")
    conn.commit()
    conn.close()

init_sqlite_db()

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

class SaveChatPayload(BaseModel):
    email: str
    title: str
    messages: list

@app.post("/api/chats/save")
def save_user_chat(payload: SaveChatPayload, authorization: str = Header(None)):
    user_info = verify_google_identity(authorization)
    email = payload.email
    if user_info and user_info.get("email"):
        email = user_info["email"]
    if not email:
        return {"status": "error", "message": "Unauthorized user."}
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM user_chats WHERE user_email = ? AND title = ?", (email, payload.title))
        existing = cursor.fetchone()
        msgs_json = json.dumps(payload.messages)
        if existing:
            cursor.execute("UPDATE user_chats SET messages_json = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (msgs_json, existing["id"]))
        else:
            cursor.execute("INSERT INTO user_chats (user_email, title, messages_json) VALUES (?, ?, ?)", (email, payload.title, msgs_json))
        conn.commit()
        conn.close()
        return {"status": "success"}
    except Exception as e:
        print(f"[DB ERROR] save_user_chat failed: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/api/chats/history")
def get_user_chat_history(email: str, authorization: str = Header(None)):
    user_info = verify_google_identity(authorization)
    if user_info and user_info.get("email"):
        email = user_info["email"]
    if not email:
        return {"history": []}
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT title, messages_json FROM user_chats WHERE user_email = ? ORDER BY updated_at DESC", (email,))
        rows = cursor.fetchall()
        conn.close()
        history = []
        for r in rows:
            try:
                msgs = json.loads(r["messages_json"])
            except Exception:
                msgs = []
            history.append({"title": r["title"], "messages": msgs})
        return {"history": history}
    except Exception as e:
        print(f"[DB ERROR] get_user_chat_history failed: {e}")
        return {"history": []}

@app.get("/api/health")
def health_check():
    return {"status": "ok", "service": "Dora AI Backend", "database": "active"}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 10000))
    print(f"Starting Dora AI Backend on port {port}...")
    uvicorn.run(app, host="0.0.0.0", port=port)
