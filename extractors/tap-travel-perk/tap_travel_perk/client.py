"""REST client handling, including TravelPerkStream base class."""

from __future__ import annotations

import decimal
import sys
from typing import TYPE_CHECKING, Any, ClassVar

from singer_sdk import SchemaDirectory, StreamSchema
from singer_sdk.authenticators import APIKeyAuthenticator
from singer_sdk.helpers.jsonpath import extract_jsonpath
from singer_sdk.pagination import BaseAPIPaginator, OffsetPaginator  # noqa: TC002
from singer_sdk.streams import RESTStream

from tap_travel_perk import schemas

if sys.version_info >= (3, 12):
    from typing import override
else:
    from typing_extensions import override

if TYPE_CHECKING:
    from collections.abc import Iterable

    import requests
    from singer_sdk.helpers.types import Context
    from singer_sdk.streams.rest import HTTPRequest, PageContext


# TODO: Delete this is if not using json files for schema definition
SCHEMAS_DIR = SchemaDirectory(schemas)


class TravelPerkStream(RESTStream):
    """TravelPerk stream class."""

    # Update this value if necessary or override `parse_response`.
    records_jsonpath = "$[*]"

    page_size = 50

    schema: ClassVar[StreamSchema] = StreamSchema(SCHEMAS_DIR)

    @override
    @property
    def url_base(self) -> str:
        """Return the API URL root, configurable via tap settings."""
        # TODO: hardcode a value here, or retrieve it from self.config
        return self.config["api_url"]

    @override
    @property
    def authenticator(self) -> APIKeyAuthenticator:
        """An authenticator object."""

        api_key: str = self.config["api_key"]
        return APIKeyAuthenticator(
            key="Authorization",
            value=f"ApiKey {api_key}",
            location="header",
        )

    @property
    @override
    def http_headers(self) -> dict:
        """A dictionary of HTTP headers."""

        headers = {
            "Api-Version": "1"
        }

        return headers

    @override
    def get_new_paginator(self) -> BaseAPIPaginator | None:
        """Create a new pagination helper instance.

        If the source API can make use of the `next_page_token_jsonpath`
        attribute, or it contains a `X-Next-Page` header in the response
        then you can remove this method.

        If you need custom pagination that uses page numbers, "next" links, or
        other approaches, please read the guide: https://sdk.meltano.com/en/v0.25.0/guides/pagination-classes.html.

        Returns:
            A pagination helper instance, or ``None`` to indicate pagination
            is not supported.
        """
        return OffsetPaginator(start_value=0, page_size=self.page_size)

    @override
    def get_http_request(self, *, page: PageContext[Any]) -> HTTPRequest:
        """Return a request object for this stream.

        Args:
            page: An object containing the stream partition or context dictionary,
                and the next page token if applicable.

        Returns:
            An HTTP request for this stream.
        """
        request = super().get_http_request(page=page)
        request.params["limit"] = self.page_size
        request.params["offset"] = page.next_page_token

        return request

    @override
    def parse_response(self, response: requests.Response) -> Iterable[dict]:
        """Parse the response and return an iterator of result records.

        Args:
            response: The HTTP ``requests.Response`` object.

        Yields:
            Each record from the source.
        """
        # TODO: Parse response body and return a set of records.
        yield from extract_jsonpath(
            self.records_jsonpath,
            input=response.json(parse_float=decimal.Decimal),
        )

    @override
    def post_process(
        self,
        row: dict,
        context: Context | None = None,
    ) -> dict | None:
        """As needed, append or transform raw data to match expected structure.

        Note: As of SDK v0.47.0, this method is automatically executed for all stream types.
        You should not need to call this method directly in custom `get_records` implementations.

        Args:
            row: An individual record from the stream.
            context: The stream context.

        Returns:
            The updated record dictionary, or ``None`` to skip the record.
        """
        # TODO: Delete this method if not needed.
        return row
