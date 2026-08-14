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
from langchain_groq import ChatGroq
from langchain_community.tools.tavily_search import TavilySearchResults
from langgraph.prebuilt import create_react_agent
from langgraph.checkpoint.memory import MemorySaver

# 1. Load Environment Variables
load_dotenv(override=True)

if not os.environ.get("GROQ_API_KEY"):
    print("[WARNING] GROQ_API_KEY environment variable is missing!")
if not os.environ.get("TAVILY_API_KEY"):
    print("[WARNING] TAVILY_API_KEY environment variable is missing!")

if os.environ.get("GEMINI_API_KEY") and not os.environ.get("GOOGLE_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = os.environ.get("GEMINI_API_KEY")

from langchain_google_genai import ChatGoogleGenerativeAI


# Available Models (Dora Flash vs Dora Pro)
MODELS = {
    "flash": "llama-3.1-8b-instant",
    "pro": "llama-3.3-70b-versatile"
}

def get_agent(model_key="flash"):
    groq_model = MODELS.get(model_key, MODELS["flash"])
    llm = ChatGroq(model=groq_model, temperature=0.2)

    search_tool = TavilySearchResults(max_results=3)
    tools = [search_tool]
    memory = MemorySaver()

    instructions = """You are Dora, a helpful, advanced AI assistant (built with high intelligence & real-time search).

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

    return create_react_agent(llm, tools, checkpointer=memory, prompt=instructions)

agent_flash = get_agent("flash")
agent_pro = get_agent("pro")


limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])
app = FastAPI(title="Gemini Agent API")
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

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default_user"
    model: str = "flash" # 'flash' or 'pro'
    deep_research: bool = False

class ModifyRequest(BaseModel):
    text: str
    instruction: str # 'shorter', 'longer', 'simpler'

@app.post("/chat/modify")
async def modify_text(req: ModifyRequest):
    llm = ChatGroq(model="llama-3.1-8b-instant", temperature=0.3)
    prompt = f"Rewrite the following text to make it {req.instruction}:\n\n{req.text}"
    response = await llm.ainvoke(prompt)
    return {"modified_text": response.content}

def needs_web_search(message: str, deep_research: bool) -> bool:
    if deep_research:
        return True
    search_keywords = ["search", "latest", "news", "today", "weather", "current", "stock price", "who is", "what happened"]
    return any(kw in message.lower() for kw in search_keywords)

async def generate_ai_stream(message: str, session_id: str, model_key: str = "flash", deep_research: bool = False):
    if needs_web_search(message, deep_research):
        agent = agent_pro if model_key == "pro" else agent_flash
        config = {"configurable": {"thread_id": session_id}}
        async for event in agent.astream_events({"messages": [("user", message)]}, config, version="v2"):
            kind = event["event"]
            if kind == "on_chat_model_stream":
                content = event["data"]["chunk"].content
                if content:
                    yield f"data: {json.dumps({'content': content})}\n\n"
            elif kind == "on_tool_start":
                yield f"data: {json.dumps({'content': '\n[🌐 Searching Google & Tavily Web...]\n'})}\n\n"
    else:
        groq_model = MODELS.get(model_key, MODELS["flash"])
        llm = ChatGroq(model=groq_model, temperature=0.2, streaming=True)
        messages = [
            ("system", "You are Dora, a helpful AI assistant. Answer accurately, clearly, with markdown formatting, code blocks, and headers."),
            ("user", message)
        ]
        async for chunk in llm.astream(messages):
            if chunk.content:
                yield f"data: {json.dumps({'content': chunk.content})}\n\n"

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

            if needs_web_search(user_message, deep_research):
                agent = agent_pro if model_key == "pro" else agent_flash
                config = {"configurable": {"thread_id": session_id}}

                async for event in agent.astream_events({"messages": [("user", user_message)]}, config, version="v2"):
                    kind = event["event"]
                    
                    if kind == "on_tool_start":
                        tool_name = event.get("name", "Google Search")
                        await websocket.send_json({"type": "tool_start", "tool": tool_name})
                    elif kind == "on_tool_end":
                        output = event.get("data", {}).get("output", [])
                        sources = []
                        if isinstance(output, list):
                            for item in output:
                                if isinstance(item, dict) and "url" in item:
                                    sources.append({"title": item.get("title", "Web Source"), "url": item["url"]})
                        await websocket.send_json({"type": "tool_end", "sources": sources})
                    elif kind == "on_chat_model_stream":
                        content = event["data"]["chunk"].content
                        if content:
                            await websocket.send_json({"type": "token", "content": content})
            else:
                groq_model = MODELS.get(model_key, MODELS["flash"])
                llm = ChatGroq(model=groq_model, temperature=0.2, streaming=True)
                system_prompt = """You are Dora, a helpful, advanced AI assistant.

GENERATIVE UI INSTRUCTIONS:
You can render rich, interactive UI components directly in the chat interface by appending one of the following JSON blocks at the very end of your response when relevant:

1. WEATHER CARD (if user asks about weather or forecast):
[UI:WEATHER_CARD]{"location": "City, Country", "temp": "22°C", "condition": "Sunny / Clear"}[/UI:WEATHER_CARD]

2. TASK CHECKLIST CARD (if user asks for a step-by-step plan, recipe, todo list, or checklist):
[UI:TASK_CARD]{"title": "Action Plan Title", "tasks": ["Task item 1", "Task item 2", "Task item 3"]}[/UI:TASK_CARD]

3. CHART CARD (if user asks for numerical data comparisons or statistics):
[UI:CHART_CARD]{"title": "Data Comparison", "labels": ["Category A", "Category B", "Category C"], "values": [35, 55, 80]}[/UI:CHART_CARD]

RULE: Write clear, markdown-formatted responses with headers, bullet points, and code blocks where appropriate."""
                
                messages = [
                    ("system", system_prompt),
                    ("user", user_message)
                ]
                async for chunk in llm.astream(messages):
                    if chunk.content:
                        await websocket.send_json({"type": "token", "content": chunk.content})

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
        page_count = 1
        
        if filename.lower().endswith(".pdf"):
            pdf_reader = pypdf.PdfReader(io.BytesIO(raw_bytes))
            page_count = len(pdf_reader.pages)
            page_texts = []
            for idx, page in enumerate(pdf_reader.pages):
                txt = page.extract_text() or ""
                if txt.strip():
                    page_texts.append(f"--- Page {idx+1} ---\n{txt.strip()}")
            extracted_text = "\n\n".join(page_texts)
        else:
            extracted_text = raw_bytes.decode("utf-8", errors="ignore")
            
        return {
            "status": "success",
            "filename": filename,
            "page_count": page_count,
            "char_count": len(extracted_text),
            "extracted_text": extracted_text[:20000]
        }
    except Exception as e:
        print(f"[DOCUMENT UPLOAD ERROR]: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/")
@limiter.limit("120/minute")
def health(request: Request):
    return {"status": "online", "name": "Gemini Web App API", "models": ["llama-3.1-8b-instant", "llama-3.3-70b-versatile"]}

import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

class EmailNotificationRequest(BaseModel):
    email: str
    name: str

@app.post("/api/send-welcome-email")
def send_welcome_email(req: EmailNotificationRequest):
    resend_api_key = os.environ.get("RESEND_API_KEY", "")
    if resend_api_key:
        try:
            import requests
            res = requests.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {resend_api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "from": "Dora AI <onboarding@resend.dev>",
                    "to": [req.email],
                    "subject": "🔑 Security Notification: Signed in to Dora AI",
                    "html": f"""
                    <div style="font-family: Arial, sans-serif; background-color: #0B0C10; color: #FFFFFF; padding: 30px; border-radius: 12px;">
                      <h2 style="color: #4285F4;">Dora AI Sign-In Notification</h2>
                      <p>Hello <b>{req.name}</b>,</p>
                      <p>Your Google Account (<b>{req.email}</b>) was successfully authenticated on <b>Dora AI</b>.</p>
                      <hr style="border: 1px solid #1F222E;" />
                      <p style="font-size: 12px; color: #888;">If this was you, no further action is required. Enjoy exploring Dora AI!</p>
                    </div>
                    """
                }
            )
            if res.status_code in (200, 201):
                print(f"[RESEND SUCCESS] Real email delivered to Gmail inbox: {req.email}")
                return {"status": "delivered", "recipient": req.email, "provider": "Resend"}
            else:
                print(f"[RESEND RESPONSE] Code {res.status_code}: {res.text}")
        except Exception as e:
            print(f"[RESEND ERROR] Could not send via Resend: {e}")

    sender_email = os.environ.get("SMTP_EMAIL", "")
    sender_password = os.environ.get("SMTP_PASSWORD", "")

    if sender_email and sender_password:
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = "Security Notification: Signed in to Dora AI"
            msg["From"] = f"Dora AI Concierge <{sender_email}>"
            msg["To"] = req.email

            html = f"""
            <div style="font-family: Arial, sans-serif; background-color: #0B0C10; color: #FFFFFF; padding: 30px; border-radius: 12px;">
              <h2 style="color: #4285F4;">Dora AI Sign-In Notification</h2>
              <p>Hello <b>{req.name}</b>,</p>
              <p>Your Google Account (<b>{req.email}</b>) was successfully authenticated on <b>Dora AI</b>.</p>
              <hr style="border: 1px solid #1F222E;" />
              <p style="font-size: 12px; color: #888;">If this was you, no further action is required. Enjoy exploring Dora AI!</p>
            </div>
            """
            msg.attach(MIMEText(html, "html"))

            with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
                server.login(sender_email, sender_password)
                server.sendmail(sender_email, req.email, msg.as_string())
            print(f"[SMTP SUCCESS] Real email delivered to Gmail inbox: {req.email}")
            return {"status": "delivered", "recipient": req.email}
        except Exception as e:
            print(f"[SMTP ERROR] Could not deliver email via SMTP: {e}")

    print(f"[GMAIL ENGINE] OAuth sign-in notification logged for {req.email} ({req.name})")
    return {
        "status": "success",
        "message": f"Real-time sign-in event logged for {req.email}",
        "recipient": req.email
    }

DB_FILE = "user_chats.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            title TEXT NOT NULL,
            messages_json TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_email, title)
        )
    ''')
    conn.commit()

    legacy_file = "user_chats.json"
    if os.path.exists(legacy_file):
        try:
            with open(legacy_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            for email, threads in data.items():
                for thread in threads:
                    t_title = thread.get("title", "Untitled Chat")
                    t_msgs = json.dumps(thread.get("messages", []), ensure_ascii=False)
                    cursor.execute('''
                        INSERT INTO user_chats (user_email, title, messages_json, updated_at)
                        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT(user_email, title) DO UPDATE SET
                            messages_json=excluded.messages_json,
                            updated_at=CURRENT_TIMESTAMP
                    ''', (email, t_title, t_msgs))
            conn.commit()
            print("[DB MIGRATION] Legacy user_chats.json successfully migrated into SQLite DB.")
        except Exception as e:
            print(f"[DB MIGRATION WARNING] Failed to migrate user_chats.json: {e}")
    conn.close()

init_db()

def get_db_connection():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

class SaveChatRequest(BaseModel):
    email: str
    title: str
    messages: list

@app.post("/api/chats/save")
@limiter.limit("40/minute")
def save_user_chat(request: Request, req: SaveChatRequest, authorization: str = Header(None)):
    user_info = verify_google_identity(authorization)
    if user_info and user_info.get("email"):
        req.email = user_info["email"]
    if not req.email:
        return {"status": "ignored", "reason": "No email provided"}
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        msgs_json = json.dumps(req.messages, ensure_ascii=False)
        cursor.execute('''
            INSERT INTO user_chats (user_email, title, messages_json, updated_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(user_email, title) DO UPDATE SET
                messages_json=excluded.messages_json,
                updated_at=CURRENT_TIMESTAMP
        ''', (req.email, req.title, msgs_json))
        conn.commit()
        
        cursor.execute("SELECT COUNT(*) FROM user_chats WHERE user_email = ?", (req.email,))
        total_threads = cursor.fetchone()[0]
        conn.close()
        return {"status": "saved", "title": req.title, "total_threads": total_threads}
    except Exception as e:
        print(f"[DB ERROR] save_user_chat failed: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/api/chats/history")
@limiter.limit("40/minute")
def get_user_chat_history(request: Request, email: str, authorization: str = Header(None)):
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
            history.append({
                "title": r["title"],
                "messages": msgs
            })
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
    uvicorn.run("main:app", host="0.0.0.0", port=port)
