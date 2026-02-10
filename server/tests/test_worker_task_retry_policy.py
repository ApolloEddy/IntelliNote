from app.worker.retry_policy import is_non_retryable_error


def test_ssl_eof_is_non_retryable():
    exc = RuntimeError("SSLEOFError: EOF occurred in violation of protocol")
    assert is_non_retryable_error(exc) is True


def test_auth_error_is_non_retryable():
    exc = RuntimeError("AuthenticationError: invalid api key")
    assert is_non_retryable_error(exc) is True


def test_random_error_is_retryable():
    exc = RuntimeError("temporary timeout")
    assert is_non_retryable_error(exc) is False
