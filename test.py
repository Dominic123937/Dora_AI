import urllib.request
import json

def send_message(message, session_id="test_123"):
    """
    Sends a message to the chatbot and prints the streaming response.
    """
    data = json.dumps({"message": message, "session_id": session_id}).encode("utf-8")
    
    req = urllib.request.Request(
        "http://127.0.0.1:8000/chat",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            buffer = ""
            for line in response:
                line_str = line.decode("utf-8")
                buffer += line_str
                
                # When we hit a double newline, we have a complete SSE event
                if "\n\n" in buffer:
                    event_data = buffer.split("data: ", 1)[1].strip()
                    buffer = "" # Reset buffer
                    
                    if not event_data:
                        continue
                        
                    try:
                        parsed = json.loads(event_data)
                        if "content" in parsed:
                            print(parsed["content"], end="", flush=True)
                        elif "tool_start" in parsed:
                            print(f"\n[🔧 Using Tool: {parsed['name']}]")
                        elif "tool_end" in parsed:
                            print(f"[✅ Tool finished. Data received!]\n")
                    except json.JSONDecodeError:
                        pass # Ignore malformed chunks
            print() # Final newline
    except urllib.error.URLError as e:
        print(f"Error connecting to server: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    print("--- Testing Delhi Protests Query ---")
    send_message("What is the latest news on the Delhi protest?")