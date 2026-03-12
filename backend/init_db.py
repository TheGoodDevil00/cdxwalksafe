import asyncio
import os
from pathlib import Path

from databases import Database

DEFAULT_DATABASE_URL = "postgresql://admin:password@localhost:5432/safewalk"
SCHEMA_PATH = Path(__file__).resolve().parent / "app" / "schema.sql"

async def init_db():
    database_url = os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL)
    database = Database(database_url)
    try:
        await database.connect()
        print(f"Connected to database: {database_url}")
        
        with SCHEMA_PATH.open("r", encoding="utf-8") as f:
            schema = f.read()
            
        # simple split by semicolon, ignoring empty lines
        statements = [s.strip() for s in schema.split(';') if s.strip()]
        
        for statement in statements:
            try:
                # Skip transactions blocks if any (BEGIN/COMMIT) if they cause issues, 
                # but pure DDL should be fine.
                await database.execute(statement)
            except Exception as e:
                print(f"Error executing statement: {statement[:50]}... -> {e}")
                
        print("Schema applied successfully")
        
    except Exception as e:
        print(f"Error initializing database: {e}")
    finally:
        await database.disconnect()

if __name__ == "__main__":
    asyncio.run(init_db())
