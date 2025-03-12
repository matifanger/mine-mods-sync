from fastapi import FastAPI, UploadFile, HTTPException
from fastapi.responses import FileResponse
import os
import shutil
import json
from typing import List
from pathlib import Path
import logging

# Set up logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = FastAPI()

# Get mods directory from environment variable
MODS_DIR = os.getenv('MODS_DIR')
if not MODS_DIR:
    raise ValueError("MODS_DIR environment variable is required")

logger.info(f"MODS_DIR set to: {MODS_DIR}")

# If it doesn't exist, create it, throw an error
try:
    # Check if the directory exists
    if not os.path.exists(MODS_DIR):
        raise FileNotFoundError(f"MODS_DIR does not exist: {MODS_DIR}")
    # Check if the directory is a directory
    if not os.path.isdir(MODS_DIR):
        raise NotADirectoryError(f"MODS_DIR is not a directory: {MODS_DIR}")
except Exception as e:
    raise

@app.get("/mods")
async def list_mods():
    """List all mods in the server"""
    try:
        mods = []
        for file in os.listdir(MODS_DIR):
            if file.endswith('.jar'):
                path = os.path.join(MODS_DIR, file)
                mods.append({
                    "name": file,
                    "size": os.path.getsize(path),
                    "modified": os.path.getmtime(path)
                })
        logger.info(f"Listed {len(mods)} mods")
        return mods
    except Exception as e:
        logger.error(f"Error in list_mods: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/mods/{mod_name}")
async def download_mod(mod_name: str):
    """Download a specific mod"""
    file_path = os.path.join(MODS_DIR, mod_name)
    if not os.path.exists(file_path):
        logger.warning(f"Mod not found: {mod_name}")
        raise HTTPException(status_code=404, detail="Mod not found")
    logger.info(f"Returning mod: {mod_name}")
    return FileResponse(file_path, filename=mod_name)

@app.post("/mods/sync")
async def sync_mods(files: List[UploadFile]):
    """Sync mods with the provided list - will delete mods not in the list"""
    try:
        current_mods = {f for f in os.listdir(MODS_DIR) if f.endswith('.jar')}
        uploaded_mods = set()

        # Upload new mods
        for file in files:
            if not file.filename.endswith('.jar'):
                continue

            uploaded_mods.add(file.filename)
            file_path = os.path.join(MODS_DIR, file.filename)
            
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)
            logger.info(f"Uploaded mod: {file.filename}")

        # Delete mods not in the uploaded list
        for mod in current_mods - uploaded_mods:
            try:
                os.remove(os.path.join(MODS_DIR, mod))
                logger.info(f"Deleted mod: {mod}")
            except Exception as e:
                logger.error(f"Failed to delete {mod}: {str(e)}")

        return {"status": "synced", "uploaded": len(uploaded_mods), "deleted": len(current_mods - uploaded_mods)}
    except Exception as e:
        logger.error(f"Error in sync_mods: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/mods/upload")
async def upload_mod(file: UploadFile):
    """Upload a single mod without sync"""
    if not file.filename.endswith('.jar'):
        raise HTTPException(status_code=400, detail="Only .jar files are allowed")
    
    file_path = os.path.join(MODS_DIR, file.filename)
    try:
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        logger.info(f"Uploaded mod: {file.filename}")
        return {"filename": file.filename, "status": "uploaded"}
    except Exception as e:
        logger.error(f"Error in upload_mod: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)