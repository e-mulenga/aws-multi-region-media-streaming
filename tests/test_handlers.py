"""Offline unit tests for the Lambda handlers (no AWS calls)."""
import importlib.util
import os
import sys
import types
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    boto3 = types.ModuleType("boto3")
    boto3.client = mock.MagicMock()
    boto3.resource = mock.MagicMock()
    cond = types.ModuleType("boto3.dynamodb.conditions")
    cond.Key = mock.MagicMock()
    cond.Attr = mock.MagicMock()
    sys.modules.update({"boto3": boto3, "boto3.dynamodb": types.ModuleType("boto3.dynamodb"), "boto3.dynamodb.conditions": cond})
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, "lambda", name, "handler.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ContentApi(unittest.TestCase):
    def test_health(self):
        m = load("content-api")
        r = m.lambda_handler({"requestContext": {"http": {"method": "GET"}}, "rawPath": "/api/health"}, None)
        self.assertEqual(r["statusCode"], 200)

    def test_search_requires_query(self):
        m = load("content-api")
        r = m.lambda_handler({"requestContext": {"http": {"method": "GET"}}, "rawPath": "/api/search"}, None)
        self.assertEqual(r["statusCode"], 400)

    def test_ready_item_gets_relative_url(self):
        m = load("content-api")
        item = m._enrich_item({"content_id": "abc", "status": "READY", "version": 1})
        self.assertEqual(item["streaming_url"], "/vod/abc/hls/index.m3u8")


class Ingestion(unittest.TestCase):
    def test_validate_rejects_missing_key(self):
        m = load("media-ingestion")
        self.assertFalse(m._validate({"detail": {}})["valid"])

    def test_transcode_outputs_have_audio_and_index_destination(self):
        m = load("media-ingestion")
        client = mock.MagicMock()
        client.create_job.return_value = {"Job": {"Id": "j1"}}
        m._get_mediaconvert_client = lambda: client
        m.OUTPUT_BUCKET = "out"
        m._transcode({"validation": {"Payload": {"bucket": "b", "key": "k.mp4", "content_id": "c1"}}})
        settings = client.create_job.call_args.kwargs["Settings"]
        group = settings["OutputGroups"][0]
        self.assertTrue(group["OutputGroupSettings"]["HlsGroupSettings"]["Destination"].endswith("/hls/index"))
        for out in group["Outputs"]:
            self.assertIn("AudioDescriptions", out)


class Analytics(unittest.TestCase):
    def test_rejects_unknown_event(self):
        m = load("analytics")
        ev = {"requestContext": {"http": {"method": "POST"}}, "rawPath": "/api/analytics/events", "body": '{"event_type": "nope"}'}
        self.assertEqual(m.lambda_handler(ev, None)["statusCode"], 400)


if __name__ == "__main__":
    unittest.main()
