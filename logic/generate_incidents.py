import csv
import random
import uuid
import math
import os
from datetime import datetime, timedelta

# Configuration
NUM_REPORTS = 200

# Robust path handling
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "incident_reports_dummy.csv")

# Pune geographic constraints 
CENTER_LAT = 18.5204
CENTER_LON = 73.8567
RADIUS_KM = 2.5

# Incident types and contextual dummy descriptions
INCIDENT_TYPES = [
    "Harrasment", 
    "Poor lighting", 
    "Suspicious Activity", 
    "Stalking", 
    "Unsafe infrastructure"
]

DESCRIPTIONS = {
    "Harrasment": [
        "A group of people were catcalling pedestrians.",
        "Someone yelled obscenities at me while passing by.",
        "Aggressive panhandling at the intersection."
    ],
    "Poor lighting": [
        "Streetlights are completely out on this block.",
        "Very dark alleyway, visibility is almost zero.",
        "Flickering lights make it hard to see the footpath."
    ],
    "Suspicious Activity": [
        "Group of individuals loitering around parked cars.",
        "Someone looking into ground-floor windows.",
        "Unattended bag left near the bus stand."
    ],
    "Stalking": [
        "A person followed me for three consecutive blocks.",
        "Noticed the same two-wheeler circling the area slowly.",
        "Someone was taking photos of people walking by without consent.",
        "A person followed me for three consecutive blocks."
    ],
    "Unsafe infrastructure": [
        "Deep open manhole right in the middle of the sidewalk.",
        "Broken pavement forcing pedestrians to walk on the busy street.",
        "Construction debris blocking the entire walking path."
    ]
}

def generate_random_point(center_lat, center_lon, radius_km):
    """Generates a random coordinate within a given radius."""
    radius_in_degrees = radius_km / 111.0
    u = random.random()
    v = random.random()
    w = radius_in_degrees * math.sqrt(u)
    t = 2 * math.pi * v
    x = w * math.cos(t)
    y = w * math.sin(t)
    
    # Adjust for longitude distortion
    new_lon = x / math.cos(math.radians(center_lat)) + center_lon
    new_lat = y + center_lat
    return round(new_lat, 6), round(new_lon, 6)

def generate_random_timestamp(days_back=30):
    """Generates a random timestamp within the last X days."""
    now = datetime.now()
    random_days = random.uniform(0, days_back)
    random_date = now - timedelta(days=random_days)
    # Format to match standard PostgreSQL timestamp format
    return random_date.strftime("%Y-%m-%d %H:%M:%S")

def generate_csv():
    # Ensure the output directory exists before writing
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Headers matching the Supabase table schema exactly
    headers = ["id", "latitude", "longitude", "incident_type", "description", "created_at"]
    
    with open(OUTPUT_FILE, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(headers)
        
        for _ in range(NUM_REPORTS):
            record_id = str(uuid.uuid4())
            lat, lon = generate_random_point(CENTER_LAT, CENTER_LON, RADIUS_KM)
            incident_type = random.choice(INCIDENT_TYPES)
            description = random.choice(DESCRIPTIONS[incident_type])
            created_at = generate_random_timestamp()
            
            writer.writerow([record_id, lat, lon, incident_type, description, created_at])
            
    print(f"Successfully generated {NUM_REPORTS} records at {OUTPUT_FILE}")

if __name__ == "__main__":
    generate_csv()