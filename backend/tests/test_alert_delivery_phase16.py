import os
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from fastapi.testclient import TestClient

from app.main import app
from app.routers.admin import ADMIN_API_KEY
from app.services.alert_delivery_service import TrustedContact, send_sms


def _response(status_code: int, *, json_body=None, text_body: str = "") -> httpx.Response:
    request = httpx.Request("POST", "https://www.fast2sms.com/dev/bulkV2")
    if json_body is not None:
        return httpx.Response(status_code, json=json_body, request=request)
    return httpx.Response(status_code, text=text_body, request=request)


class AlertDeliveryServiceTests(unittest.IsolatedAsyncioTestCase):
    @patch.dict(os.environ, {"FAST2SMS_API_KEY": "test-key"}, clear=False)
    @patch("app.services.alert_delivery_service.httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_send_sms_accepts_string_true_response(self, post_mock: AsyncMock):
        post_mock.return_value = _response(
            200,
            json_body={
                "return": "true",
                "message": ["SMS sent successfully"],
                "request_id": "req-123",
            },
        )

        success, error = await send_sms(
            contact=TrustedContact(name="Alice", phone="+91 98765 43210"),
            lat=18.5204,
            lon=73.8567,
            sender_name="WalkSafe Test",
        )

        self.assertTrue(success)
        self.assertIsNone(error)
        self.assertEqual(post_mock.await_count, 1)
        self.assertEqual(post_mock.await_args.kwargs["data"]["numbers"], "9876543210")

    @patch.dict(os.environ, {"FAST2SMS_API_KEY": "test-key"}, clear=False)
    @patch("app.services.alert_delivery_service.httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_send_sms_accepts_request_id_even_without_true_return(
        self,
        post_mock: AsyncMock,
    ):
        post_mock.return_value = _response(
            200,
            json_body={
                "return": False,
                "message": ["queued"],
                "request_id": "req-456",
            },
        )

        success, error = await send_sms(
            contact=TrustedContact(name="Bob", phone="9876543210"),
            lat=18.5204,
            lon=73.8567,
            sender_name="WalkSafe Test",
        )

        self.assertTrue(success)
        self.assertIsNone(error)

    @patch.dict(os.environ, {"FAST2SMS_API_KEY": "test-key"}, clear=False)
    @patch("app.services.alert_delivery_service.httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_send_sms_returns_parse_error_for_non_json(self, post_mock: AsyncMock):
        post_mock.return_value = _response(200, text_body="gateway maintenance")

        success, error = await send_sms(
            contact=TrustedContact(name="Charlie", phone="9876543210"),
            lat=18.5204,
            lon=73.8567,
            sender_name="WalkSafe Test",
        )

        self.assertFalse(success)
        self.assertIn("unparseable response", error)


class AdminSmsRouteTests(unittest.TestCase):
    def test_admin_test_sms_endpoint_returns_send_result(self):
        with patch(
            "app.services.alert_delivery_service.send_sms",
            new=AsyncMock(return_value=(True, None)),
        ):
            with TestClient(app) as client:
                response = client.post(
                    "/admin/test-sms?phone=9876543210",
                    headers={"X-Admin-Key": ADMIN_API_KEY},
                )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "phone": "9876543210",
                "sms_sent": True,
                "error": None,
                "note": "Check backend logs for the raw Fast2SMS response.",
            },
        )


if __name__ == "__main__":
    unittest.main()
