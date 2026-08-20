"""Stream type classes for tap-travel-perk."""

from __future__ import annotations

from singer_sdk import typing as th  # JSON Schema typing helpers

from tap_travel_perk.client import TravelPerkStream


class BookingsStream(TravelPerkStream):
    """Define bookings stream."""

    name = "bookings"
    path = "/bookings"
    primary_keys = ("id",)
    replication_key = "modified"
    records_jsonpath = "$.bookings[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique booking identifier"),
        th.Property("modified", th.StringType, description="Last modification timestamp"),
        th.Property("start", th.StringType, description="Start time of the booking"),
        th.Property("end", th.StringType, description="End time of the booking"),
        th.Property("type", th.StringType, description="Service category: flight, hotel, train, car, other"),
        th.Property("status", th.StringType, description="Booking status: confirmed or cancelled"),
        th.Property("trip_id", th.StringType, description="Parent trip identifier"),
        th.Property(
            "references",
            th.ArrayType(
                th.ObjectType(
                    th.Property("type", th.StringType),
                    th.Property("value", th.StringType),
                )
            ),
            description="External entity references",
        ),
        th.Property(
            "location",
            th.ObjectType(
                th.Property("name", th.StringType),
                th.Property("address", th.StringType),
                th.Property("latitude", th.StringType),
                th.Property("longitude", th.StringType),
                th.Property("iata_code", th.StringType),
            ),
            description="Service location; populated for hotel or car types",
        ),
        th.Property(
            "drop_off_location",
            th.ObjectType(
                th.Property("name", th.StringType),
                th.Property("address", th.StringType),
                th.Property("latitude", th.StringType),
                th.Property("longitude", th.StringType),
                th.Property("iata_code", th.StringType),
            ),
            description="Car-only drop-off point; null for other types",
        ),
        th.Property(
            "legs",
            th.ArrayType(
                th.ObjectType(
                    th.Property(
                        "segments",
                        th.ArrayType(
                            th.ObjectType(
                                th.Property(
                                    "origin",
                                    th.ObjectType(
                                        th.Property(
                                            "location",
                                            th.ObjectType(
                                                th.Property("name", th.StringType),
                                                th.Property("address", th.StringType),
                                                th.Property("latitude", th.StringType),
                                                th.Property("longitude", th.StringType),
                                                th.Property("iata_code", th.StringType),
                                            ),
                                        ),
                                        th.Property("time", th.StringType),
                                    ),
                                ),
                                th.Property(
                                    "destination",
                                    th.ObjectType(
                                        th.Property(
                                            "location",
                                            th.ObjectType(
                                                th.Property("name", th.StringType),
                                                th.Property("address", th.StringType),
                                                th.Property("latitude", th.StringType),
                                                th.Property("longitude", th.StringType),
                                                th.Property("iata_code", th.StringType),
                                            ),
                                        ),
                                        th.Property("time", th.StringType),
                                    ),
                                ),
                                th.Property("external_id", th.StringType, description="Journey identifier such as a flight number"),
                            )
                        ),
                    ),
                )
            ),
            description="Transport legs; populated for flight or train types",
        ),
    ).to_dict()


class CostCentersStream(TravelPerkStream):
    """Define cost centers stream."""

    name = "cost_centers"
    path = "/cost_centers"
    primary_keys = ("id",)
    replication_key = None
    records_jsonpath = "$.cost_centers[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique identifier of the cost center"),
        th.Property("name", th.StringType, description="Name of the cost center"),
        th.Property("count_users", th.IntegerType, description="The number of users assigned to this cost center"),
    ).to_dict()


class InvoiceProfilesStream(TravelPerkStream):
    """Define invoice profiles stream."""

    name = "invoice_profiles"
    path = "/profiles"
    primary_keys = ("id",)
    replication_key = None
    records_jsonpath = "$.profiles[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique identifier"),
        th.Property("name", th.StringType, description="Profile name"),
        th.Property("payment_method_type", th.StringType, description="Payment method: credit_card, instant_direct_debit, manual_direct_debit, bank_transfer, sepa"),
        th.Property("billing_period", th.StringType, description="Billing cadence: instant, weekly, biweekly, monthly"),
        th.Property("currency", th.StringType, description="3-char currency code"),
        th.Property(
            "billing_information",
            th.ObjectType(
                th.Property("legal_name", th.StringType),
                th.Property("vat_number", th.StringType),
                th.Property("address_line_1", th.StringType),
                th.Property("address_line_2", th.StringType),
                th.Property("city", th.StringType),
                th.Property("postal_code", th.StringType),
                th.Property("country_name", th.StringType),
            ),
            description="Legal billing entity details",
        ),
    ).to_dict()


class InvoiceLinesStream(TravelPerkStream):
    """Define invoice lines stream."""

    name = "invoice_lines"
    path = "/invoices/lines"
    primary_keys = ("id",)
    replication_key = "expense_date"
    records_jsonpath = "$.lines[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique identifier"),
        th.Property("expense_date", th.StringType, description="Date the sale/refund was incurred"),
        th.Property("quantity", th.IntegerType, description="Units sold, based on number of travelers"),
        th.Property("unit_price", th.StringType, description="Per-unit taxable amount"),
        th.Property("non_taxable_unit_price", th.StringType, description="Per-unit non-taxable amount"),
        th.Property("tax_percentage", th.StringType, description="Applicable tax rate"),
        th.Property("tax_amount", th.StringType, description="Calculated tax amount"),
        th.Property("tax_regime", th.StringType, description="Tax regime code: STAR, G-VAT-R, GROSS"),
        th.Property("total_amount", th.StringType, description="Total including tax and non-taxable amounts"),
        th.Property(
            "metadata",
            th.ObjectType(
                th.Property("trip_id", th.StringType),
                th.Property("trip_name", th.StringType),
                th.Property("service", th.StringType),
                th.Property("related_vertical", th.StringType),
                th.Property(
                    "travelers",
                    th.ArrayType(
                        th.ObjectType(
                            th.Property("name", th.StringType),
                            th.Property("email", th.StringType),
                            th.Property("external_id", th.StringType),
                        )
                    ),
                ),
                th.Property("start_date", th.StringType),
                th.Property("end_date", th.StringType),
                th.Property("cost_center", th.StringType),
                th.Property("labels", th.ArrayType(th.StringType)),
                th.Property(
                    "vendor",
                    th.ObjectType(
                        th.Property("code", th.StringType),
                        th.Property("name", th.StringType),
                    ),
                ),
                th.Property("out_of_policy", th.BooleanType),
                th.Property(
                    "approvers",
                    th.ArrayType(
                        th.ObjectType(
                            th.Property("name", th.StringType),
                            th.Property("email", th.StringType),
                            th.Property("external_id", th.StringType),
                        )
                    ),
                ),
                th.Property(
                    "booker",
                    th.ObjectType(
                        th.Property("name", th.StringType),
                        th.Property("email", th.StringType),
                        th.Property("external_id", th.StringType),
                    ),
                ),
                th.Property("service_location", th.CustomType({"type": "object"})),
                th.Property("include_breakfast", th.BooleanType),
            ),
            description="Contextual data about user, trip, and service",
        ),
        th.Property("invoice_serial_number", th.StringType, description="Unique invoice identifier"),
        th.Property("profile_id", th.StringType, description="Globally unique payment/invoice profile ID"),
        th.Property("profile_name", th.StringType, description="Name of the payment/invoice profile"),
        th.Property("invoice_mode", th.StringType, description="Legal document type"),
        th.Property("invoice_status", th.StringType, description="Current invoice status"),
        th.Property("issuing_date", th.StringType, description="Date the invoice was issued"),
        th.Property("due_date", th.StringType, description="Payment deadline date"),
        th.Property("currency", th.StringType, description="ISO 4217 currency code"),
    ).to_dict()


class InvoicesStream(TravelPerkStream):
    """Define invoices stream."""

    name = "invoices"
    path = "/invoices"
    primary_keys = ("serial_number",)
    replication_key = "issuing_date"
    records_jsonpath = "$.invoices[*]"

    schema = th.PropertiesList(
        th.Property("serial_number", th.StringType, description="Globally unique invoice identifier"),
        th.Property("profile_id", th.StringType, description="Unique identifier for the invoice profile"),
        th.Property("profile_name", th.StringType, description="Name of the invoice profile"),
        th.Property(
            "billing_information",
            th.ObjectType(
                th.Property("legal_name", th.StringType),
                th.Property("vat_number", th.StringType),
                th.Property("address_line_1", th.StringType),
                th.Property("address_line_2", th.StringType),
                th.Property("city", th.StringType),
                th.Property("postal_code", th.StringType),
                th.Property("country_name", th.StringType),
            ),
            description="Legal customer info",
        ),
        th.Property("mode", th.StringType, description="Legal document type: reseller, intermediary, gross, credit-reseller, credit-intermediary, credit-gross, Mixed, passthrough"),
        th.Property("status", th.StringType, description="Invoice status: paid or unpaid"),
        th.Property("issuing_date", th.StringType, description="Date the invoice closes"),
        th.Property("billing_period", th.StringType, description="Billing cycle: instant, weekly, biweekly, monthly"),
        th.Property("from_date", th.StringType, description="First day of billing period"),
        th.Property("to_date", th.StringType, description="Last day of billing period"),
        th.Property("due_date", th.StringType, description="Payment deadline"),
        th.Property("currency", th.StringType, description="Billing currency code (ISO 4217)"),
        th.Property("total", th.StringType, description="Total amount including tax"),
        th.Property("credit_used_for_customer_payment", th.StringType, description="TK credit applied to invoice"),
        th.Property(
            "taxes_summary",
            th.ArrayType(
                th.ObjectType(
                    th.Property("tax_regime", th.StringType),
                    th.Property("subtotal", th.StringType),
                    th.Property("tax_percentage", th.StringType),
                    th.Property("tax_amount", th.StringType),
                    th.Property("total", th.StringType),
                )
            ),
            description="Tax breakdown per regime or percentage",
        ),
        th.Property("reference", th.StringType, description="Additional text reference"),
    ).to_dict()


class SuppliersStream(TravelPerkStream):
    """Define suppliers stream."""

    name = "suppliers"
    path = "/suppliers"
    primary_keys = ("id",)
    replication_key = None
    records_jsonpath = "$.suppliers[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique identifier of the supplier"),
        th.Property("name", th.StringType, description="Name of the supplier"),
        th.Property("bookings", th.ArrayType(th.StringType), description="List of booking IDs related to this supplier"),
    ).to_dict()


class TripsStream(TravelPerkStream):
    """Define trips stream."""

    name = "trips"
    path = "/trips"
    primary_keys = ("id",)
    replication_key = "modified"
    records_jsonpath = "$.trips[*]"

    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique trip identifier"),
        th.Property("modified", th.StringType, description="Last modification timestamp"),
        th.Property("start", th.StringType, description="Earliest departure time; null if cancelled"),
        th.Property("end", th.StringType, description="Latest arrival time; null if cancelled"),
        th.Property("status", th.StringType, description="Trip status: booked or cancelled"),
        th.Property("trip_name", th.StringType, description="Name or purpose of the trip"),
        th.Property(
            "start_location",
            th.ObjectType(
                th.Property("name", th.StringType),
                th.Property("address", th.StringType),
                th.Property("latitude", th.StringType),
                th.Property("longitude", th.StringType),
                th.Property("iata_code", th.StringType),
            ),
            description="Origin location; null if cancelled",
        ),
        th.Property(
            "end_location",
            th.ObjectType(
                th.Property("name", th.StringType),
                th.Property("address", th.StringType),
                th.Property("latitude", th.StringType),
                th.Property("longitude", th.StringType),
                th.Property("iata_code", th.StringType),
            ),
            description="Destination location; null if cancelled",
        ),
        th.Property("booker_id", th.StringType, description="Identifier of the user who booked the trip"),
    ).to_dict()


class UsersStream(TravelPerkStream):
    """Define custom stream."""

    name = "users"
    path = "/users"
    primary_keys = ("id",)
    replication_key = None
    records_jsonpath = "$.users[*]"
    schema = th.PropertiesList(
        th.Property("id", th.StringType, description="Unique identifier for the user"),
        th.Property("user_name", th.StringType, description="Authentication identifier, usually an email address"),
        th.Property(
            "name",
            th.ObjectType(
                th.Property("first_name", th.StringType),
                th.Property("last_name", th.StringType),
                th.Property("middle_name", th.StringType),
                th.Property("title", th.StringType),
            ),
            description="User's name",
        ),
        th.Property("preferred_language", th.StringType, description="User's preferred written or spoken language"),
        th.Property("locale", th.StringType, description="Default location for localizing currency, date/time, and number formats"),
        th.Property("active", th.BooleanType, description="True if able to log in, false otherwise"),
        th.Property("job_title", th.StringType, description="The user's job title"),
        th.Property("email", th.StringType, description="Email address"),
    ).to_dict()
