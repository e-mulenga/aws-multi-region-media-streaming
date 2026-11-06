"""Media platform Content API Lambda — catalogue, search, metadata operations."""
import json, logging, os, boto3
from boto3.dynamodb.conditions import Key, Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ddb     = boto3.resource("dynamodb")
TABLE   = os.environ.get("CONTENT_TABLE_NAME", "")
BASE    = ("https://" + os.environ["PUBLIC_BASE_HOST"]) if os.environ.get("PUBLIC_BASE_HOST") else ""
ENV     = os.environ.get("ENVIRONMENT", "dev")

def lambda_handler(event, context):
    method     = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path       = event.get("rawPath", "/")
    path_params = event.get("pathParameters") or {}
    qs          = event.get("queryStringParameters") or {}

    logger.info("%s %s", method, path)

    if method == "GET" and path.endswith("/health"):
        return _response(200, {"status": "ok"})

    try:
        if method == "GET" and "/search" in path:
            return _search(qs.get("q", ""), qs.get("limit", "20"))
        elif method == "GET" and path_params.get("id"):
            return _get_content(path_params["id"])
        elif method == "GET":
            return _list_content(qs.get("status", "READY"), qs.get("limit", "20"))
        elif method == "POST":
            body = json.loads(event.get("body", "{}"))
            return _create_content(body)
        else:
            return _response(405, {"error": "Method not allowed"})
    except Exception as exc:
        logger.error("Handler error: %s", exc, exc_info=True)
        return _response(500, {"error": "Internal server error"})

def _list_content(status, limit):
    table = ddb.Table(TABLE)
    resp  = table.query(
        IndexName="status-created-index",
        KeyConditionExpression=Key("status").eq(status),
        Limit=int(limit),
        ScanIndexForward=False
    )
    items = [_enrich_item(i) for i in resp.get("Items", [])]
    return _response(200, {"items": items, "count": len(items)})

def _get_content(content_id):
    table = ddb.Table(TABLE)
    resp  = table.get_item(Key={"content_id": content_id, "version": 1})
    item  = resp.get("Item")
    if not item:
        return _response(404, {"error": "Content not found"})
    return _response(200, _enrich_item(item))

def _search(query, limit):
    if not query:
        return _response(400, {"error": "Query parameter 'q' is required"})
    table = ddb.Table(TABLE)
    resp  = table.scan(
        FilterExpression=Attr("title").contains(query) | Attr("description").contains(query),
        Limit=int(limit)
    )
    items = [_enrich_item(i) for i in resp.get("Items", [])]
    return _response(200, {"items": items, "count": len(items), "query": query})

def _create_content(body):
    import uuid
    from datetime import datetime, timezone
    content_id = str(uuid.uuid4())
    now        = datetime.now(timezone.utc).isoformat()
    item = {
        "content_id"  : content_id,
        "version"     : 1,
        "title"       : body.get("title", "Untitled"),
        "description" : body.get("description", ""),
        "status"      : "PENDING",
        "created_at"  : now,
        "updated_at"  : now,
        "environment" : ENV,
        "tags"        : body.get("tags", []),
    }
    ddb.Table(TABLE).put_item(Item=item)
    return _response(201, item)

def _enrich_item(item):
    cid = item.get("content_id", "")
    if cid and item.get("status") == "READY":
        item["streaming_url"] = f"{BASE}/vod/{cid}/hls/index.m3u8"
    for k in ["version"]: item.pop(k, None)
    return item

def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps(body, default=str)
    }
