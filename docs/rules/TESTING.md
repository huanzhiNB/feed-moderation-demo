# Tests

Write a small number of focused unit tests on the parts that carry the moderation rules — the
stream derivation (`visibleFeed = fetchedPages - blockedCreators - reportedSekais`) and the
play/pause settle logic are the ones that matter. UI test coverage is explicitly out of scope
per the assignment — don't add it or a testing framework/harness for it.
