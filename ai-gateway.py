#!/usr/bin/env python3
"""
Hermis AI Gateway
Unified interface for local AI models with OpenAI-compatible API
"""

import os
import json
import logging
import asyncio
from typing import Optional, List, Dict, Any
from datetime import datetime
import httpx

from fastapi import FastAPI, HTTPException, BackgroundTasks, Header
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
import uvicorn

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
QDRANT_BASE_URL = os.getenv("QDRANT_BASE_URL", "http://qdrant:6333")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
ENABLE_RAG = os.getenv("ENABLE_RAG", "true").lower() == "true"
ENABLE_METRICS = os.getenv("ENABLE_METRICS", "true").lower() == "true"
RATE_LIMIT = int(os.getenv("RATE_LIMIT", "100"))
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "300"))

# Initialize FastAPI app
app = FastAPI(
    title="Hermis AI Gateway",
    description="Unified AI inference gateway with OpenAI-compatible API",
    version="1.0.0"
)

# Request/Response models
class Message(BaseModel):
    role: str = Field(..., description="Role: system, user, or assistant")
    content: str = Field(..., description="Message content")

class ChatRequest(BaseModel):
    model: str = Field(..., description="Model ID")
    messages: List[Message] = Field(..., description="Message history")
    temperature: float = Field(default=0.7, ge=0, le=2)
    max_tokens: Optional[int] = Field(default=None)
    top_p: float = Field(default=0.9, ge=0, le=1)
    top_k: Optional[int] = Field(default=None)
    stream: bool = Field(default=False)
    stop: Optional[List[str]] = Field(default=None)
    system: Optional[str] = Field(default=None, description="System prompt")

class ChatResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[Dict[str, Any]]
    usage: Dict[str, int]

class EmbeddingRequest(BaseModel):
    model: str = Field(..., description="Embedding model")
    input: str | List[str] = Field(..., description="Text to embed")

class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: List[Dict[str, Any]]
    model: str
    usage: Dict[str, int]

class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    owned_by: str = "hermis"
    created: int
    capability: str
    context_window: int
    parameters: int

class RAGRequest(BaseModel):
    query: str = Field(..., description="Query text")
    model: str = Field(..., description="Model for generation")
    collection: str = Field(..., description="Vector database collection")
    top_k: int = Field(default=5, ge=1, le=50)
    similarity_threshold: float = Field(default=0.7, ge=0, le=1)
    stream: bool = Field(default=False)

# Model registry
class ModelRegistry:
    def __init__(self):
        self.models: Dict[str, Dict[str, Any]] = {}
        self.cache = {}
        self.metrics = {
            "requests": 0,
            "tokens": 0,
            "errors": 0,
            "latency_ms": []
        }

    async def discover_models(self, retries: int = 3):
        """Discover available models from Ollama (with retries)"""
        for attempt in range(1, retries + 1):
            try:
                async with httpx.AsyncClient() as client:
                    response = await client.get(
                        f"{OLLAMA_BASE_URL}/api/tags",
                        timeout=15
                    )
                if response.status_code == 200:
                    data = response.json()
                    for model in data.get("models", []):
                        self.register_model(
                            model["name"],
                            model_type="text-generation",
                            context_window=4096,
                            parameters=model.get("size", 0),
                            metadata=model
                        )
                    logger.info(f"Discovered {len(self.models)} models")
                    return True
                logger.error(f"Failed to discover models: {response.status_code}")
            except Exception as e:
                logger.error(f"Error discovering models (attempt {attempt}/{retries}): {e}")
                if attempt < retries:
                    await asyncio.sleep(2)
        return False

    async def ensure_models(self):
        """Lazily discover models if the registry is empty (self-healing)."""
        if not self.models:
            await self.discover_models()

    def register_model(self, model_id: str, model_type: str,
                      context_window: int, parameters: int, metadata: Dict = None):
        """Register a model in the registry"""
        self.models[model_id] = {
            "id": model_id,
            "type": model_type,
            "context_window": context_window,
            "parameters": parameters,
            "created": int(datetime.now().timestamp()),
            "metadata": metadata or {}
        }
        logger.info(f"Registered model: {model_id}")

    def get_model(self, model_id: str) -> Optional[Dict]:
        """Get model info"""
        return self.models.get(model_id)

    def list_models(self) -> List[Dict]:
        """List all available models"""
        return list(self.models.values())

# Initialize model registry
registry = ModelRegistry()

@app.on_event("startup")
async def startup():
    """Initialize on startup"""
    logger.info("Hermis AI Gateway starting up...")
    await registry.discover_models()
    logger.info("Gateway initialization complete")

# API endpoints

@app.get("/v1/models")
async def list_models():
    """List available models"""
    await registry.ensure_models()
    return {
        "object": "list",
        "data": [
            {
                "id": m["id"],
                "object": "model",
                "owned_by": "hermis",
                "created": m["created"],
                "permission": [],
                "root": m["id"],
                "parent": None
            }
            for m in registry.list_models()
        ]
    }

@app.get("/v1/models/{model_id}")
async def get_model(model_id: str):
    """Get model details"""
    model = registry.get_model(model_id)
    if not model:
        raise HTTPException(status_code=404, detail=f"Model {model_id} not found")

    return {
        "id": model["id"],
        "object": "model",
        "owned_by": "hermis",
        "created": model["created"],
        "permission": [],
        "root": model["id"],
        "parent": None
    }

@app.post("/v1/chat/completions")
async def chat_completion(request: ChatRequest):
    """OpenAI-compatible chat completion endpoint"""
    try:
        # Validate model exists (lazily discover if registry is empty)
        await registry.ensure_models()
        model = registry.get_model(request.model)
        if not model:
            raise HTTPException(status_code=404, detail=f"Model {request.model} not found")

        # Prepare messages
        messages = [{"role": m.role, "content": m.content} for m in request.messages]

        # Add system message if provided
        if request.system:
            messages.insert(0, {"role": "system", "content": request.system})

        # Call Ollama
        async with httpx.AsyncClient() as client:
            ollama_request = {
                "model": request.model,
                "messages": messages,
                "temperature": request.temperature,
                "top_p": request.top_p,
                "stream": request.stream,
                "options": {}
            }

            if request.top_k:
                ollama_request["options"]["top_k"] = request.top_k
            if request.max_tokens:
                ollama_request["options"]["num_predict"] = request.max_tokens

            response = await client.post(
                f"{OLLAMA_BASE_URL}/api/chat",
                json=ollama_request,
                timeout=REQUEST_TIMEOUT
            )

            if response.status_code != 200:
                logger.error(f"Ollama error: {response.text}")
                raise HTTPException(status_code=500, detail="Model inference failed")

            if request.stream:
                async def generate():
                    async for line in response.aiter_lines():
                        if line:
                            try:
                                chunk = json.loads(line)
                                yield f"data: {json.dumps(chunk)}\n\n"
                            except json.JSONDecodeError:
                                continue

                return StreamingResponse(generate(), media_type="text/event-stream")
            else:
                result = response.json()

                # Format as OpenAI response
                return {
                    "id": f"hermis-{datetime.now().timestamp()}",
                    "object": "chat.completion",
                    "created": int(datetime.now().timestamp()),
                    "model": request.model,
                    "choices": [{
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": result["message"]["content"]
                        },
                        "finish_reason": "stop"
                    }],
                    "usage": {
                        "prompt_tokens": len(str(messages)),
                        "completion_tokens": len(result["message"]["content"].split()),
                        "total_tokens": len(str(messages)) + len(result["message"]["content"].split())
                    }
                }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Chat completion error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/embeddings")
async def create_embedding(request: EmbeddingRequest):
    """Create embeddings"""
    try:
        # Validate model (lazily discover if registry is empty)
        await registry.ensure_models()
        model = registry.get_model(request.model)
        if not model:
            raise HTTPException(status_code=404, detail=f"Model {request.model} not found")

        # Handle both string and list input
        texts = [request.input] if isinstance(request.input, str) else request.input

        embeddings = []
        async with httpx.AsyncClient() as client:
            for i, text in enumerate(texts):
                response = await client.post(
                    f"{OLLAMA_BASE_URL}/api/embeddings",
                    json={"model": request.model, "prompt": text},
                    timeout=REQUEST_TIMEOUT
                )

                if response.status_code != 200:
                    raise HTTPException(status_code=500, detail="Embedding failed")

                data = response.json()
                embeddings.append({
                    "object": "embedding",
                    "index": i,
                    "embedding": data["embedding"]
                })

        return {
            "object": "list",
            "data": embeddings,
            "model": request.model,
            "usage": {
                "prompt_tokens": sum(len(t.split()) for t in texts),
                "total_tokens": sum(len(t.split()) for t in texts)
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/rag/query")
async def rag_query(request: RAGRequest):
    """RAG query with vector database"""
    if not ENABLE_RAG:
        raise HTTPException(status_code=501, detail="RAG not enabled")

    try:
        # Get embeddings for query
        async with httpx.AsyncClient() as client:
            # Create query embedding
            embed_response = await client.post(
                f"{OLLAMA_BASE_URL}/api/embeddings",
                json={"model": "nomic-embed-text", "prompt": request.query},
                timeout=REQUEST_TIMEOUT
            )

            if embed_response.status_code != 200:
                raise HTTPException(status_code=500, detail="Embedding failed")

            query_embedding = embed_response.json()["embedding"]

            # Search vector database
            search_response = await client.post(
                f"{QDRANT_BASE_URL}/collections/{request.collection}/points/search",
                json={
                    "vector": query_embedding,
                    "limit": request.top_k,
                    "score_threshold": request.similarity_threshold
                },
                timeout=REQUEST_TIMEOUT
            )

            if search_response.status_code != 200:
                raise HTTPException(status_code=500, detail="Vector search failed")

            search_results = search_response.json()

            # Format context
            context = "\n".join([
                r["payload"].get("text", "")
                for r in search_results.get("result", [])
            ])

            # Generate response with context
            system_prompt = f"""You are a helpful AI assistant.
Use the following context to answer the user's question:

Context:
{context}"""

            # Call model with RAG context
            chat_request = ChatRequest(
                model=request.model,
                messages=[Message(role="user", content=request.query)],
                system=system_prompt,
                stream=request.stream
            )

            return await chat_completion(chat_request)

    except Exception as e:
        logger.error(f"RAG query error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "models_loaded": len(registry.models),
        "version": "1.0.0"
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    metrics_text = f"""# HELP hermis_gateway_requests_total Total requests processed
# TYPE hermis_gateway_requests_total counter
hermis_gateway_requests_total {registry.metrics['requests']}

# HELP hermis_gateway_errors_total Total errors
# TYPE hermis_gateway_errors_total counter
hermis_gateway_errors_total {registry.metrics['errors']}

# HELP hermis_gateway_tokens_total Total tokens processed
# TYPE hermis_gateway_tokens_total counter
hermis_gateway_tokens_total {registry.metrics['tokens']}

# HELP hermis_gateway_models_loaded Number of loaded models
# TYPE hermis_gateway_models_loaded gauge
hermis_gateway_models_loaded {len(registry.models)}
"""
    return metrics_text

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level=LOG_LEVEL.lower(),
        access_log=True
    )
