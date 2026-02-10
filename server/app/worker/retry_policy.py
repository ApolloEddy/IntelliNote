NON_RETRYABLE_ERROR_MARKERS = (
    "SSLEOFError",
    "AuthenticationError",
    "Missing DashScope embedding API key",
)


def is_non_retryable_error(exc: Exception) -> bool:
    text = repr(exc)
    return any(marker in text for marker in NON_RETRYABLE_ERROR_MARKERS)
