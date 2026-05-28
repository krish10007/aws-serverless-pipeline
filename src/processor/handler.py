"""
Processor Lambda — Entry point of the pipeline.

Triggered by S3 upload, reads CSV/JSON files,
transforms records, pushes to SQS, emits CloudWatch metrics.
"""

import json
import csv
import io
import os
import time
import uuid
import logging
import boto3
from datetime import datetime, timezone

# -------------------------------------------------------
# STRUCTURED LOGGING SETUP
# Every log line is valid JSON — CloudWatch can query these
# -------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log(level, message, **kwargs):
    """
    Emit a structured JSON log line.
    Every log has: timestamp, level, message, lambda_request_id, plus any extras.
    
    Usage:
        log("INFO", "Processing started", bucket="my-bucket", key="raw/data.csv")
    """
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "message": message,
        "function": os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "local"),
        **kwargs  # any extra fields you pass in
    }
    # Use the appropriate logger method
    getattr(logger, level.lower())(json.dumps(entry))


# -------------------------------------------------------
# AWS CLIENTS
# Initialized outside the handler so they're reused
# across Lambda invocations (warm start optimization)
# -------------------------------------------------------
s3_client = boto3.client("s3")
sqs_client = boto3.client("sqs")
cloudwatch = boto3.client("cloudwatch")

# Environment variables — set by Terraform, not hardcoded
SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "serverless-pipeline")


# -------------------------------------------------------
# CLOUDWATCH CUSTOM METRICS
# This is what separates this project from tutorials.
# We push our own metrics — not just the default Lambda ones.
# -------------------------------------------------------
def push_metric(metric_name, value, unit="Count", dimensions=None):
    """
    Push a single custom metric to CloudWatch.
    
    Metrics appear under the namespace: ServerlessPipeline/Processor
    You'll see them in CloudWatch → Metrics → Custom Namespaces
    """
    if dimensions is None:
        dimensions = []

    # Always include environment as a dimension
    # This lets you filter metrics by prod vs dev
    dimensions.append({"Name": "Environment", "Value": ENVIRONMENT})

    try:
        cloudwatch.put_metric_data(
            Namespace=f"{PROJECT_NAME}/Processor",
            MetricData=[
                {
                    "MetricName": metric_name,
                    "Value": value,
                    "Unit": unit,
                    "Dimensions": dimensions,
                    "Timestamp": datetime.now(timezone.utc),
                }
            ],
        )
    except Exception as e:
        # Never let metric pushing crash the main flow
        log("WARNING", "Failed to push metric", metric=metric_name, error=str(e))


# -------------------------------------------------------
# FILE PARSING
# -------------------------------------------------------
def parse_csv(content: str) -> list[dict]:
    """Parse CSV string into list of dicts."""
    reader = csv.DictReader(io.StringIO(content))
    return [row for row in reader]


def parse_json(content: str) -> list[dict]:
    """Parse JSON string — handles both a list and a single object."""
    data = json.loads(content)
    # If someone uploads a single JSON object instead of a list, wrap it
    return data if isinstance(data, list) else [data]


def parse_file(key: str, content: str) -> list[dict]:
    """Route to the right parser based on file extension."""
    if key.endswith(".csv"):
        return parse_csv(content)
    elif key.endswith(".json"):
        return parse_json(content)
    else:
        raise ValueError(f"Unsupported file type: {key}")


# -------------------------------------------------------
# RECORD TRANSFORMATION
# Clean and normalize each record before it hits DynamoDB
# -------------------------------------------------------
def transform_record(record: dict, source_bucket: str, source_key: str) -> dict:
    """
    Transform a raw record into a clean, enriched record.
    
    Adds:
    - record_id: unique ID for deduplication
    - ingested_at: ISO timestamp of when we processed it
    - source_bucket / source_key: full lineage back to the original file
    
    Cleans:
    - Strips whitespace from all string values
    - Converts empty strings to None
    """
    transformed = {}

    for k, v in record.items():
        # Normalize key: lowercase, replace spaces with underscores
        clean_key = k.strip().lower().replace(" ", "_")
        
        # Clean value
        if isinstance(v, str):
            v = v.strip()
            v = None if v == "" else v
        
        transformed[clean_key] = v

    # Add pipeline metadata
    transformed["record_id"] = str(uuid.uuid4())
    transformed["ingested_at"] = datetime.now(timezone.utc).isoformat()
    transformed["source_bucket"] = source_bucket
    transformed["source_key"] = source_key

    return transformed


def validate_record(record: dict) -> tuple[bool, str]:
    """
    Basic validation — extend this with your actual business rules.
    Returns (is_valid, reason_if_invalid)
    """
    if not record:
        return False, "empty record"
    # Add your own validation rules here as the project grows
    return True, ""


# -------------------------------------------------------
# SQS PUBLISHING
# Send records to SQS in batches of 10 (SQS batch limit)
# -------------------------------------------------------
def send_to_sqs(records: list[dict]) -> tuple[int, int]:
    """
    Send records to SQS in batches of 10.
    Returns (success_count, failure_count)
    """
    success_count = 0
    failure_count = 0

    # Chunk into batches of 10 — SQS send_message_batch limit
    for i in range(0, len(records), 10):
        batch = records[i:i + 10]

        entries = [
            {
                "Id": str(idx),  # ID within this batch (0-9)
                "MessageBody": json.dumps(record),
                "MessageGroupId": "pipeline",         # required for FIFO queues
                "MessageDeduplicationId": record["record_id"],  # prevents duplicates
            }
            for idx, record in enumerate(batch)
        ]

        try:
            response = sqs_client.send_message_batch(
                QueueUrl=SQS_QUEUE_URL,
                Entries=entries,
            )
            success_count += len(response.get("Successful", []))
            failure_count += len(response.get("Failed", []))

            if response.get("Failed"):
                log("ERROR", "Some SQS messages failed",
                    failed=response["Failed"])

        except Exception as e:
            log("ERROR", "SQS batch send failed",
                batch_start=i, error=str(e))
            failure_count += len(batch)

    return success_count, failure_count


# -------------------------------------------------------
# LAMBDA HANDLER — entry point AWS calls
# -------------------------------------------------------
def handler(event, context):
    """
    Main handler — AWS calls this when S3 uploads a file.
    
    'event' contains the S3 event data: bucket name, object key, etc.
    'context' contains Lambda runtime info: request ID, remaining time, etc.
    """
    pipeline_start = time.perf_counter()
    lambda_request_id = context.aws_request_id

    log("INFO", "Processor Lambda invoked",
        request_id=lambda_request_id,
        record_count=len(event.get("Records", [])))

    total_processed = 0
    total_failed = 0

    # S3 can batch multiple file events into one Lambda invocation
    # Loop handles each file separately
    for s3_record in event.get("Records", []):
        bucket = s3_record["s3"]["bucket"]["name"]
        key = s3_record["s3"]["object"]["key"]
        file_size = s3_record["s3"]["object"].get("size", 0)

        log("INFO", "Processing file",
            bucket=bucket,
            key=key,
            file_size_bytes=file_size)

        file_start = time.perf_counter()

        try:
            # 1. Download file from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            content = response["Body"].read().decode("utf-8")

            # 2. Parse
            raw_records = parse_file(key, content)
            log("INFO", "File parsed",
                key=key,
                raw_record_count=len(raw_records))

            # 3. Validate + transform each record
            valid_records = []
            for raw in raw_records:
                is_valid, reason = validate_record(raw)
                if not is_valid:
                    log("WARNING", "Record failed validation",
                        reason=reason, record=raw)
                    total_failed += 1
                    push_metric("ValidationErrors", 1)
                    continue

                transformed = transform_record(raw, bucket, key)
                valid_records.append(transformed)

            # 4. Send valid records to SQS
            if valid_records:
                sent, failed = send_to_sqs(valid_records)
                total_processed += sent
                total_failed += failed

            # 5. Per-file latency metric
            file_latency_ms = (time.perf_counter() - file_start) * 1000
            push_metric("FileProcessingLatency", file_latency_ms, unit="Milliseconds")

            log("INFO", "File processing complete",
                key=key,
                records_sent_to_sqs=total_processed,
                latency_ms=round(file_latency_ms, 2))

        except Exception as e:
            log("ERROR", "Failed to process file",
                bucket=bucket,
                key=key,
                error=str(e),
                error_type=type(e).__name__)
            push_metric("ProcessingErrors", 1)
            # Re-raise so Lambda marks this invocation as failed
            raise

    # 6. Push aggregate metrics for this invocation
    total_latency_ms = (time.perf_counter() - pipeline_start) * 1000
    push_metric("RecordsProcessed", total_processed)
    push_metric("RecordsFailed", total_failed)
    push_metric("TotalLatency", total_latency_ms, unit="Milliseconds")

    log("INFO", "Invocation complete",
        total_processed=total_processed,
        total_failed=total_failed,
        total_latency_ms=round(total_latency_ms, 2))

    return {
        "statusCode": 200,
        "records_processed": total_processed,
        "records_failed": total_failed,
    }