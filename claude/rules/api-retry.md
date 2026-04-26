## API Error Retry

When encountering a model access API error (e.g., overloaded, rate limit, transient server error), retry the failed tool call every 5 seconds, up to a maximum of 10 retries. If all retries are exhausted, report the error to the user.
