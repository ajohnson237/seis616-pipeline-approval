from app import health_check_page


def test_main_page():
    result = health_check_page()
    assert result == 'OK'
