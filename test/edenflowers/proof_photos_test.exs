defmodule Edenflowers.ProofPhotosTest do
  use ExUnit.Case, async: true

  alias Edenflowers.ProofPhotos

  defp root, do: Application.fetch_env!(:edenflowers, :proof_photo_root)

  defp entry(name) do
    %{client_name: name, client_type: "image/jpeg", client_size: 8}
  end

  defp write_tmp do
    path = Path.join(System.tmp_dir!(), "src-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "JPEGDATA")
    path
  end

  test "stores the original under a generated path and returns metadata" do
    {:ok, meta} = ProofPhotos.store(write_tmp(), entry("user vacation photo.JPG"))

    assert meta.photo_media_type == "image/jpeg"
    assert meta.photo_original_filename == "user vacation photo.JPG"
    assert String.starts_with?(meta.photo_path, "proof_photos/")
    assert String.ends_with?(meta.photo_path, ".jpg")
    assert File.exists?(Path.join(root(), meta.photo_path))

    # The stored path is server-generated, not derived from the client filename.
    refute meta.photo_path =~ "vacation"
  end

  test "delete removes the stored original" do
    {:ok, meta} = ProofPhotos.store(write_tmp(), entry("proof.jpg"))
    assert File.exists?(Path.join(root(), meta.photo_path))

    assert :ok = ProofPhotos.delete(meta.photo_path)
    refute File.exists?(Path.join(root(), meta.photo_path))
  end

  test "delete tolerates a nil path" do
    assert :ok = ProofPhotos.delete(nil)
  end

  test "signed_url builds an imgproxy URL from the relative path" do
    url = ProofPhotos.signed_url("proof_photos/abc.jpg")
    assert is_binary(url)
  end

  test "rejects an unrecognised extension by falling back to .jpg" do
    {:ok, meta} = ProofPhotos.store(write_tmp(), entry("payload.exe"))
    assert String.ends_with?(meta.photo_path, ".jpg")
  end
end
