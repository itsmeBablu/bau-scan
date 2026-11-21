import base64
import hashlib
import io
import os
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

import app


class RecognitionTests(unittest.TestCase):
    def request(self):
        output = io.BytesIO()
        Image.new("RGB", (64, 48), (120, 40, 10)).save(output, "JPEG")
        raw = output.getvalue()
        return {"schemaVersion": 1, "frameID": "11111111-1111-1111-1111-111111111111",
                "imageJPEG": base64.b64encode(raw).decode(), "imageSHA256": hashlib.sha256(raw).hexdigest(),
                "maskWidth": 64, "maskHeight": 48}

    def test_valid_image_and_hash_binding(self):
        request = self.request()
        raw, w, h = app.validate_input(request)
        self.assertEqual((w, h), (64, 48))
        self.assertTrue(raw.startswith(b"\xff\xd8"))
        request["imageSHA256"] = "wrong"
        with self.assertRaises(HTTPException):
            app.validate_input(request)

    def test_rejects_rotation_and_oversized_grid(self):
        request = self.request()
        request["maskWidth"] = 2000
        with self.assertRaises(HTTPException):
            app.validate_input(request)
        request["maskWidth"] = True
        with self.assertRaises(HTTPException):
            app.validate_input(request)

    def test_polygon_rle_is_row_major_and_not_a_box(self):
        result = app.polygon_instances({"instances": [{"kind": "pipe", "polygon": [[0, 0], [1000, 0], [0, 1000]]}]}, 8, 8)[0]
        pixels = [bool(i % 2) for i, run in enumerate(result["runs"]) for _ in range(run)]
        self.assertEqual(len(pixels), 64)
        self.assertTrue(pixels[0])
        self.assertFalse(pixels[-1])
        self.assertLess(sum(pixels), 64)

    def test_invalid_categories_and_polygons_are_rejected(self):
        for item in [{"kind": "boiler", "polygon": [[0, 0]] * 3},
                     {"kind": "pipe", "polygon": [[0, 0], [1001, 0], [0, 1]]},
                     {"kind": "pipe", "polygon": [[False, 0], [1, 0], [0, 1]]}]:
            with self.assertRaises(ValueError):
                app.polygon_instances({"instances": [item]}, 8, 8)

    def test_verified_google_identity_and_allowlist(self):
        claims = {"iss": "accounts.google.com", "sub": "example-subject", "email": "tester@example.com", "email_verified": True}
        with patch.dict(os.environ, {"GOOGLE_SERVER_CLIENT_ID": "server-client", "GOOGLE_ALLOWED_EMAILS": "tester@example.com"}), \
             patch.object(app.id_token, "verify_oauth2_token", return_value=claims) as verify:
            self.assertEqual(len(app.verify_user("Bearer signed-token")), 64)
            self.assertEqual(verify.call_args.args[2], "server-client")
            claims["email_verified"] = False
            with self.assertRaises(HTTPException) as error:
                app.verify_user("Bearer signed-token")
            self.assertEqual(error.exception.status_code, 403)

    def test_missing_configuration_fails_closed(self):
        with patch.dict(os.environ, {"GOOGLE_SERVER_CLIENT_ID": "", "GOOGLE_ALLOWED_EMAILS": ""}):
            with self.assertRaises(HTTPException) as error:
                app.verify_user("Bearer anything")
            self.assertEqual(error.exception.status_code, 503)

    def test_persistent_limits_and_cache(self):
        with tempfile.TemporaryDirectory() as root, patch.dict(os.environ, {"MEP_USER_DAILY_LIMIT": "1", "MEP_TOTAL_DAILY_LIMIT": "2"}):
            store = app.UsageStore(os.path.join(root, "usage.sqlite"))
            store.reserve("a")
            with self.assertRaises(HTTPException):
                store.reserve("a")
            store.reserve("b")
            with self.assertRaises(HTTPException):
                store.reserve("c")
            store.save("image-model-user", {"instances": []})
            reopened = app.UsageStore(store.path)
            self.assertEqual(reopened.lookup("image-model-user"), {"instances": []})
            self.assertIsNone(reopened.lookup("other-user"))

    def test_provider_quota_has_no_automatic_paid_fallback_or_retry(self):
        with patch.dict(os.environ, {"GEMINI_API_KEY": "test-not-real", "GEMINI_FREE_PROJECT_CONFIRMED": "true"}), \
             patch.object(app.urllib.request, "urlopen", side_effect=HTTPError("test", 429, "quota", {}, None)) as send:
            with self.assertRaises(HTTPException) as error:
                app.gemini_regions(b"image", "test-model")
            self.assertEqual(error.exception.status_code, 429)
            self.assertEqual(send.call_count, 1)

    def test_http_contract_returns_regions_bound_to_selected_image_and_reuses_cache(self):
        with tempfile.TemporaryDirectory() as root, \
             patch.object(app, "_store", app.UsageStore(os.path.join(root, "usage.sqlite"))), \
             patch.dict(os.environ, {"GEMINI_MODEL": "test-free-model"}), \
             patch.object(app, "verify_user", return_value="verified-subject"), \
             patch.object(app, "gemini_regions", return_value={"instances": [{"kind": "pipe", "polygon": [[0, 0], [1000, 0], [0, 1000]]}]}) as provider:
            with TestClient(app.app) as client:
                request = self.request()
                first = client.post("/v1/segment", json=request, headers={"Authorization": "Bearer test-id-token"})
                self.assertEqual(first.status_code, 200)
                result = first.json()
                self.assertEqual(result["imageSHA256"], request["imageSHA256"])
                self.assertEqual(result["frameID"], request["frameID"])
                self.assertEqual(sum(result["instances"][0]["runs"]), 64 * 48)
                request["frameID"] = "22222222-2222-2222-2222-222222222222"
                second = client.post("/v1/segment", json=request)
                self.assertEqual(second.json()["frameID"], request["frameID"])
                self.assertEqual(provider.call_count, 1)

    def test_http_rejects_unsigned_user_before_provider_call(self):
        with patch.dict(os.environ, {"GOOGLE_SERVER_CLIENT_ID": "server-client", "GOOGLE_ALLOWED_EMAILS": "tester@example.com"}), \
             patch.object(app, "gemini_regions") as provider:
            with TestClient(app.app) as client:
                response = client.post("/v1/segment", json=self.request())
                self.assertEqual(response.status_code, 401)
                provider.assert_not_called()


if __name__ == "__main__":
    unittest.main()
