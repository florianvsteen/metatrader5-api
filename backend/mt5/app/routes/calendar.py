from flask import Blueprint, jsonify, request
import MetaTrader5 as mt5
import logging
from datetime import datetime, timezone, timedelta
from flasgger import swag_from

calendar_bp = Blueprint('calendar', __name__)
logger = logging.getLogger(__name__)

# MT5 importance integers: 0=None, 1=Low, 2=Moderate(Medium), 3=High
# The Python MT5 package does not expose CALENDAR_IMPORTANCE_* constants
IMPORTANCE_MAP = {
    0: "None",
    1: "Low",
    2: "Medium",
    3: "High",
}

# Currencies we care about
CURRENCY_COUNTRY_MAP = {
    "USD": "US",
    "EUR": "EU",
    "GBP": "GB",
    "JPY": "JP",
    "AUD": "AU",
    "CAD": "CA",
    "CHF": "CH",
    "CNY": "CN",
}


def _format_value(raw_val) -> str:
    """
    MT5 stores calendar values multiplied by 1,000,000.
    LONG_MIN (-9223372036854775808) means the value is not set.
    Returns formatted string or empty string if not set.
    """
    LONG_MIN = -9223372036854775808
    if raw_val is None or raw_val == LONG_MIN:
        return ""
    actual = raw_val / 1_000_000
    if actual == int(actual):
        return str(int(actual))
    return f"{actual:.4f}".rstrip("0").rstrip(".")


@calendar_bp.route('/calendar', methods=['GET'])
@swag_from({
    'tags': ['Calendar'],
    'parameters': [
        {
            'name': 'from_date',
            'in': 'query',
            'type': 'string',
            'required': False,
            'description': 'Start date ISO format. Defaults to Monday of current week.'
        },
        {
            'name': 'to_date',
            'in': 'query',
            'type': 'string',
            'required': False,
            'description': 'End date ISO format. Defaults to Sunday of current week.'
        }
    ],
    'responses': {
        200: {
            'description': 'Calendar events retrieved successfully.',
            'schema': {
                'type': 'array',
                'items': {
                    'type': 'object',
                    'properties': {
                        'date':             {'type': 'string'},
                        'currency':         {'type': 'string'},
                        'impact':           {'type': 'string'},
                        'title':            {'type': 'string'},
                        'actual':           {'type': 'string'},
                        'forecast':         {'type': 'string'},
                        'previous':         {'type': 'string'},
                        'event_time':       {'type': 'string'},
                        'analysis':         {'type': 'string'},
                        'actual_sentiment': {'type': 'string'},
                    }
                }
            }
        },
        500: {'description': 'Internal server error.'}
    }
})
def get_calendar():
    """
    Get Economic Calendar
    ---
    description: >
        Returns this week's economic calendar events for major forex currencies
        using MT5's built-in calendar. Includes actual values in real-time as
        MT5 receives them from the broker feed.
    """
    try:
        now = datetime.now(timezone.utc)

        from_str = request.args.get('from_date')
        to_str   = request.args.get('to_date')

        if from_str:
            from_dt = datetime.fromisoformat(from_str.replace("Z", "+00:00"))
        else:
            from_dt = (now - timedelta(days=now.weekday())).replace(
                hour=0, minute=0, second=0, microsecond=0
            )

        if to_str:
            to_dt = datetime.fromisoformat(to_str.replace("Z", "+00:00"))
        else:
            to_dt = from_dt + timedelta(days=6, hours=23, minutes=59, seconds=59)

        events = []

        for currency in CURRENCY_COUNTRY_MAP:
            try:
                calendar_events = mt5.calendar_event_by_currency(currency)
                if not calendar_events:
                    continue

                for cal_event in calendar_events:
                    event_id = cal_event.id

                    values = mt5.calendar_value_history_by_event(
                        event_id,
                        from_dt,
                        to_dt
                    )
                    if not values:
                        continue

                    importance = IMPORTANCE_MAP.get(cal_event.importance, "None")

                    for val in values:
                        try:
                            event_dt = datetime.fromtimestamp(val.time, tz=timezone.utc)
                        except Exception:
                            continue

                        if not (from_dt <= event_dt <= to_dt):
                            continue

                        actual   = _format_value(val.actual_value)
                        forecast = _format_value(val.forecast_value)
                        previous = _format_value(val.prev_value)

                        events.append({
                            "date":             event_dt.strftime("%Y-%m-%d"),
                            "currency":         currency,
                            "impact":           importance,
                            "title":            cal_event.name,
                            "actual":           actual,
                            "forecast":         forecast,
                            "previous":         previous,
                            "event_time":       event_dt.isoformat(),
                            "analysis":         "",
                            "actual_sentiment": "neutral",
                        })

            except Exception as e:
                logger.warning(f"[CALENDAR] Error fetching {currency}: {e}")
                continue

        events.sort(key=lambda x: x["event_time"])

        logger.info(f"[CALENDAR] Returning {len(events)} events ({from_dt.date()} – {to_dt.date()})")
        return jsonify(events), 200

    except Exception as e:
        logger.error(f"[CALENDAR] Internal error: {e}")
        return jsonify({"error": "Internal server error"}), 500
