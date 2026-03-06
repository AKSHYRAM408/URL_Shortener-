"""
URL Shortener — AWS Lambda Function
Handles two operations:
  POST /shorten  → creates a short URL
  GET  /{code}   → redirects to the original URL
"""

import json
import os
import string
import random
import time
import boto3
from boto3.dynamodb.conditions import Key

# ─── DynamoDB Setup ──────────────────────────────────────────────
dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "ap-south-1"))
TABLE_NAME = os.environ.get("TABLE_NAME", "url-shortener")
table = dynamodb.Table(TABLE_NAME)

# ─── Helpers ─────────────────────────────────────────────────────
CHARS = string.ascii_letters + string.digits  # a-zA-Z0-9


def generate_short_code(length: int = 6) -> str:
    """Generate a random short code (e.g. 'aB3xZ9')."""
    return "".join(random.choices(CHARS, k=length))


def build_response(status_code: int, body: dict | str, headers: dict | None = None) -> dict:
    """Return a properly formatted API Gateway proxy response."""
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    }
    if headers:
        default_headers.update(headers)

    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body) if isinstance(body, dict) else body,
    }


# ─── Core Handlers ──────────────────────────────────────────────
def shorten_url(event: dict) -> dict:
    """
    POST /shorten
    Body: { "url": "https://example.com/very/long/path" }
    Returns: { "short_code": "aB3xZ9", "short_url": "https://<api>/<stage>/aB3xZ9" }
    """
    try:
        body = json.loads(event.get("body", "{}"))
    except (json.JSONDecodeError, TypeError):
        return build_response(400, {"error": "Invalid JSON body"})

    long_url = body.get("url", "").strip()
    if not long_url:
        return build_response(400, {"error": "Missing 'url' in request body"})

    # Basic URL validation
    if not long_url.startswith(("http://", "https://")):
        return build_response(400, {"error": "URL must start with http:// or https://"})

    # Generate a unique short code (retry on collision)
    for _ in range(5):
        short_code = generate_short_code()
        try:
            table.put_item(
                Item={
                    "short_code": short_code,
                    "long_url": long_url,
                    "created_at": int(time.time()),
                    "hits": 0,
                },
                ConditionExpression="attribute_not_exists(short_code)",
            )
            break
        except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            continue  # code already exists — try again
    else:
        return build_response(500, {"error": "Could not generate a unique short code. Try again."})

    # Build the short URL from the request context
    domain = event.get("headers", {}).get("Host", "")
    stage = event.get("requestContext", {}).get("stage", "")
    short_url = f"https://{domain}/{stage}/{short_code}" if stage else f"https://{domain}/{short_code}"

    return build_response(201, {
        "short_code": short_code,
        "short_url": short_url,
        "long_url": long_url,
    })


def redirect_url(event: dict) -> dict:
    """
    GET /{code}
    Looks up the short code in DynamoDB and returns a 301 redirect.
    """
    short_code = event.get("pathParameters", {}).get("code", "")
    if not short_code:
        return build_response(400, {"error": "Missing short code in path"})

    response = table.get_item(Key={"short_code": short_code})
    item = response.get("Item")

    if not item:
        return build_response(404, {"error": f"Short code '{short_code}' not found"})

    # Increment hit counter (fire-and-forget)
    try:
        table.update_item(
            Key={"short_code": short_code},
            UpdateExpression="SET hits = hits + :inc",
            ExpressionAttributeValues={":inc": 1},
        )
    except Exception:
        pass  # non-critical — don't block the redirect

    return build_response(301, "", headers={
        "Location": item["long_url"],
        "Cache-Control": "no-cache",
    })


def get_stats(event: dict) -> dict:
    """
    GET /stats/{code}
    Returns metadata about a short code (hit count, creation time, etc.).
    """
    short_code = event.get("pathParameters", {}).get("code", "")
    if not short_code:
        return build_response(400, {"error": "Missing short code in path"})

    response = table.get_item(Key={"short_code": short_code})
    item = response.get("Item")

    if not item:
        return build_response(404, {"error": f"Short code '{short_code}' not found"})

    return build_response(200, {
        "short_code": item["short_code"],
        "long_url": item["long_url"],
        "hits": int(item.get("hits", 0)),
        "created_at": int(item.get("created_at", 0)),
    })


# ─── Lambda Entry Point ─────────────────────────────────────────
def lambda_handler(event, context):
    """
    Main router — dispatches to the correct handler based on
    HTTP method + resource path.
    """
    http_method = event.get("httpMethod", "")
    resource = event.get("resource", "")

    # CORS preflight
    if http_method == "OPTIONS":
        return build_response(200, {"message": "OK"})

    # Route: POST /shorten
    if http_method == "POST" and resource == "/shorten":
        return shorten_url(event)

    # Route: GET /stats/{code}
    if http_method == "GET" and resource == "/stats/{code}":
        return get_stats(event)

    # Route: GET /{code}  (redirect)
    if http_method == "GET" and resource == "/{code}":
        return redirect_url(event)

    return build_response(404, {"error": "Route not found"})
