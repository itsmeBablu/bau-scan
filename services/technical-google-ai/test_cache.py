import threading
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

import app


def test_recognition_version_invalidates_cache(tmp_path):
    from test_app import RecognitionTests
    store = app.UsageStore(str(tmp_path / "usage.sqlite"))
    with patch.object(app, "_store", store), patch.dict(app.os.environ, {"GEMINI_MODEL": "test-model"}), \
         patch.object(app, "gemini_regions", return_value={"instances": []}) as provider:
        request = RecognitionTests().request()
        app.analyse(request, "user")
        app.analyse(request, "user")
        assert provider.call_count == 1
        with patch.object(app, "RECOGNITION_VERSION", "next-version"):
            app.analyse(request, "user")
        assert provider.call_count == 2


def test_identical_inflight_requests_share_result_and_failure(tmp_path):
    store = app.UsageStore(str(tmp_path / "usage.sqlite"))
    for fail in [False, True]:
        entered, release, joined = threading.Event(), threading.Event(), threading.Event()
        calls = []
        def produce():
            calls.append(1); entered.set(); assert release.wait(3)
            if fail:
                raise ValueError("provider failed")
            return {"instances": []}
        original = app.Future.result
        def waiting(future, *args, **kwargs):
            joined.set()
            return original(future, *args, **kwargs)
        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(store.singleflight, "same", produce)
            assert entered.wait(3)
            with patch.object(app.Future, "result", waiting):
                second = pool.submit(store.singleflight, "same", produce)
                assert joined.wait(3); release.set()
            for future in [first, second]:
                if fail:
                    try:
                        future.result(timeout=3)
                        assert False, "failure was not propagated"
                    except ValueError:
                        pass
                else:
                    assert future.result(timeout=3) == {"instances": []}
        assert len(calls) == 1
        assert not store.inflight


def test_cache_evicts_only_oldest_and_expires(tmp_path):
    store = app.UsageStore(str(tmp_path / "usage.sqlite"))
    for i in range(201):
        with patch.object(app.time, "time", return_value=1000 + i):
            store.save(str(i), {"item": i})
    with patch.object(app.time, "time", return_value=1201):
        assert store.lookup("0") is None
        assert store.lookup("1") == {"item": 1}
        assert store.lookup("200") == {"item": 200}
    with patch.object(app.time, "time", return_value=1201 + app.CACHE_TTL_SECONDS):
        assert store.lookup("200") is None
