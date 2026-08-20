"""TravelPerk tap class."""

from __future__ import annotations

import sys

from singer_sdk import Tap
from singer_sdk import typing as th  # JSON schema typing helpers

# TODO: Import your custom stream types here:
from tap_travel_perk import streams

if sys.version_info >= (3, 12):
    from typing import override
else:
    from typing_extensions import override


class TapTravelPerk(Tap):
    """Singer tap for TravelPerk."""

    name = "tap-travel-perk"

    config_jsonschema = th.PropertiesList(
        th.Property(
            "api_key",
            th.StringType(nullable=False),
            required=True,
            secret=True,  # Flag config as protected.
            title="Api Key",
        ),
        th.Property(
            "api_url",
            th.StringType(nullable=False),
            title="API URL",
            default="https://api.perk.com",
            description="The url for the Travel Perk API",
        ),
    ).to_dict()

    @override
    def discover_streams(self) -> list[streams.TravelPerkStream]:
        """Return a list of discovered streams.

        Returns:
            A list of discovered streams.
        """
        return [
            streams.BookingsStream(self),
            streams.CostCentersStream(self),
            streams.InvoiceLinesStream(self),
            streams.InvoiceProfilesStream(self),
            streams.InvoicesStream(self),
            streams.SuppliersStream(self),
            streams.TripsStream(self),
            streams.UsersStream(self),
        ]


if __name__ == "__main__":
    TapTravelPerk.cli()
