"""Security and ownership tests for private Studio video storage."""
from urllib.parse import urlparse

import pytest

from backend.studio_storage import S3PrivateVideoStorage, VideoStorageError


JOB = "a" * 32


class FakeS3:
    def __init__(self):
        self.objects = {}
        self.put_args = []
        self.presign_args = []

    def put_object(self, **kwargs):
        self.put_args.append(kwargs)
        self.objects[(kwargs["Bucket"], kwargs["Key"])] = kwargs["Body"]

    def head_object(self, **kwargs):
        if (kwargs["Bucket"], kwargs["Key"]) not in self.objects:
            raise KeyError("missing")
        return {"ContentLength": len(self.objects[(kwargs["Bucket"], kwargs["Key"])])}

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        self.presign_args.append((operation, Params, ExpiresIn))
        return f"https://storage.example/{Params['Key']}?expires={ExpiresIn}&signature=fake"

    def delete_object(self, **kwargs):
        self.objects.pop((kwargs["Bucket"], kwargs["Key"]), None)


def storage(max_bytes=100):
    client = FakeS3()
    return S3PrivateVideoStorage(client, "private-videos", max_video_bytes=max_bytes), client


def test_store_uses_account_scoped_key_and_server_side_encryption():
    service, client = storage()
    saved = service.store_video("account_1", JOB, b"video", "video/mp4")
    assert saved.object_key == f"users/account_1/studio/{JOB}/output.mp4"
    assert saved.size_bytes == 5
    assert client.put_args[0]["ServerSideEncryption"] == "AES256"
    assert "ACL" not in client.put_args[0]
    assert client.put_args[0]["Bucket"] == "private-videos"


def test_download_link_is_short_lived_https_and_created_after_head():
    service, client = storage()
    service.store_video("account_1", JOB, b"video", "video/mp4")
    url = service.create_download_url("account_1", JOB, "video/mp4", 120)
    assert urlparse(url).scheme == "https"
    assert client.presign_args[0][0] == "get_object"
    assert client.presign_args[0][2] == 120


def test_other_account_cannot_obtain_download_link_for_video():
    service, _ = storage()
    service.store_video("account_1", JOB, b"video", "video/mp4")
    with pytest.raises(VideoStorageError, match="non disponibile"):
        service.create_download_url("account_2", JOB, "video/mp4")


@pytest.mark.parametrize("bad_user", ["../account", "account/other", "", "a" * 129])
def test_invalid_account_id_is_rejected(bad_user):
    service, _ = storage()
    with pytest.raises(VideoStorageError):
        service.store_video(bad_user, JOB, b"video", "video/mp4")


@pytest.mark.parametrize("bad_job", ["../x", "not-a-uuid", "A" * 32])
def test_invalid_job_id_is_rejected(bad_job):
    service, _ = storage()
    with pytest.raises(VideoStorageError):
        service.store_video("account_1", bad_job, b"video", "video/mp4")


def test_size_and_content_type_limits_are_enforced_before_upload():
    service, client = storage(max_bytes=4)
    with pytest.raises(VideoStorageError, match="limite"):
        service.store_video("account_1", JOB, b"12345", "video/mp4")
    with pytest.raises(VideoStorageError, match="non supportato"):
        service.store_video("account_1", JOB, b"video", "text/html")
    assert client.put_args == []


def test_presign_expiry_is_bounded():
    service, _ = storage()
    with pytest.raises(VideoStorageError, match="Scadenza"):
        service.create_download_url("account_1", JOB, "video/mp4", 3600)


def test_storage_configuration_requires_https_endpoint():
    with pytest.raises(VideoStorageError, match="HTTPS"):
        S3PrivateVideoStorage.from_environment(
            {"STUDIO_S3_BUCKET": "private-videos", "STUDIO_S3_ENDPOINT_URL": "http://storage.example"},
            client=FakeS3(),
        )


def test_delete_is_account_scoped():
    service, client = storage()
    saved = service.store_video("account_1", JOB, b"video", "video/mp4")
    service.delete_video("account_1", JOB, "video/mp4")
    assert ("private-videos", saved.object_key) not in client.objects
