import csv
import random
import uuid
from datetime import datetime, timezone

# Generate 1000 records
rows = []
cities = ["New York", "Chicago", "San Francisco", "Austin", "Seattle", "Boston"]
domains = ["gmail.com", "yahoo.com", "outlook.com", "company.com"]

for i in range(1000):
    rows.append({
        "name": f"User {i}",
        "email": f"user{i}@{random.choice(domains)}",
        "age": random.randint(18, 65),
        "city": random.choice(cities),
        "score": round(random.uniform(0, 100), 2),
        "transaction_id": str(uuid.uuid4()),
        "created_at": datetime.now(timezone.utc).isoformat()
    })

with open("scripts/load_test_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} records")