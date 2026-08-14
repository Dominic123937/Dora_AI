import json
import os
import io
import sqlite3
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
from groq import AsyncGroq, Groq
from tavily import TavilyClient

# 1. Load Environment Variables
load_dotenv(override=True)

GROQ_KEY = os.environ.get("GROQ_API_KEY", "")
TAVILY_KEY = os.environ.get("TAVILY_API_KEY", "")

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

def get_groq_client():
    key = os.environ.get("GROQ_API_KEY") or GROQ_KEY
    if not key:
        return None
    return AsyncGroq(api_key=key)

def get_tavily_client():
    key = os.environ.get("TAVILY_API_KEY") or TAVILY_KEY
    if not key:
        return None
    return TavilyClient(api_key=key)

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
async def modify_text(req: ModifyRequest):
    key = os.environ.get("GROQ_API_KEY") or GROQ_KEY
    client = AsyncGroq(api_key=key)
    prompt = f"Rewrite the following text to make it {req.instruction}:\n\n{req.text}"
    resp = await client.chat.completions.create(
        model="llama-3.1-8b-instant",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3
    )
    return {"modified_text": resp.choices[0].message.content}

async def generate_ai_stream(message: str, session_id: str, model_key: str = "flash", deep_research: bool = False):
    client = get_groq_client()
    if not client:
        yield f"data: {json.dumps({'content': 'Configuration Error: GROQ_API_KEY is not configured on the server.'})}\n\n"
        return

    groq_model = MODELS.get(model_key, MODELS["flash"])
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    sources = []
    if needs_web_search(message, deep_research):
        tavily = get_tavily_client()
        if tavily:
            yield f"data: {json.dumps({'content': '[Searching Google & Tavily Web...]\n\n'})}\n\n"
            try:
                search_res = tavily.search(message, max_results=3)
                search_context = "\n\n--- WEB SEARCH RESULTS ---\n"
                for res in search_res.get("results", []):
                    search_context += f"Source: {res.get('title')} ({res.get('url')})\nContent: {res.get('content')}\n\n"
                    sources.append({"title": res.get("title", "Web Source"), "url": res.get("url", "")})
                messages.append({"role": "system", "content": f"The following live web search results were found for the user request:\n{search_context}\nSynthesize a complete answer using these facts and cite sources."})
            except Exception as e:
                print(f"[SEARCH ERROR] {e}")

    messages.append({"role": "user", "content": message})

    try:
        stream = await client.chat.completions.create(
            model=groq_model,
            messages=messages,
            temperature=0.2,
            stream=True
        )
        async for chunk in stream:
            token = chunk.choices[0].delta.content or ""
            if token:
                yield f"data: {json.dumps({'content': token})}\n\n"
    except Exception as e:
        yield f"data: {json.dumps({'content': f'\n\n[Error generating response: {str(e)}]'})}\n\n"

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

            client = get_groq_client()
            if not client:
                await websocket.send_json({"type": "token", "content": "Configuration notice: GROQ_API_KEY is currently missing on the server. Please check Render environment settings."})
                await websocket.send_json({"type": "done"})
                continue

            groq_model = MODELS.get(model_key, MODELS["flash"])
            messages = [{"role": "system", "content": SYSTEM_PROMPT}]

            if needs_web_search(user_message, deep_research):
                tavily = get_tavily_client()
                if tavily:
                    await websocket.send_json({"type": "tool_start", "tool": "Google Search & Tavily"})
                    try:
                        search_res = tavily.search(user_message, max_results=3)
                        sources = []
                        search_context = "\n\n--- WEB SEARCH RESULTS ---\n"
                        for res in search_res.get("results", []):
                            search_context += f"Source: {res.get('title')} ({res.get('url')})\nContent: {res.get('content')}\n\n"
                            sources.append({"title": res.get("title", "Web Source"), "url": res.get("url", "")})
                        await websocket.send_json({"type": "tool_end", "sources": sources})
                        messages.append({"role": "system", "content": f"The following live web search results were found for the user request:\n{search_context}\nSynthesize a complete answer using these facts."})
                    except Exception as e:
                        print(f"[SEARCH ERROR] {e}")

            messages.append({"role": "user", "content": user_message})

            try:
                stream = await client.chat.completions.create(
                    model=groq_model,
                    messages=messages,
                    temperature=0.2,
                    stream=True
                )
                async for chunk in stream:
                    token = chunk.choices[0].delta.content or ""
                    if token:
                        await websocket.send_json({"type": "token", "content": token})
            except Exception as e:
                print(f"[GROQ ERROR] {e}")
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
