defmodule Edenflowers.ProofPhotos.Storage do
  @moduledoc "Behaviour for writing and deleting proof-photo originals, kept small so filesystem work is testable."
  @callback put(tmp_path :: String.t(), relative_path :: String.t()) :: :ok | {:error, term()}
  @callback delete(relative_path :: String.t()) :: :ok
end

defmodule Edenflowers.ProofPhotos.LocalStorage do
  @moduledoc """
  Writes proof-photo originals, unchanged, under a persistent-volume root shared
  with imgproxy (read-only). Phoenix is the only writer.
  """
  @behaviour Edenflowers.ProofPhotos.Storage

  @impl true
  def put(tmp_path, relative_path) do
    dest = Path.join(root(), relative_path)
    File.mkdir_p!(Path.dirname(dest))

    case File.cp(tmp_path, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(relative_path) do
    Path.join(root(), relative_path) |> File.rm()
    :ok
  end

  defp root, do: Application.fetch_env!(:edenflowers, :proof_photo_root)
end

defmodule Edenflowers.ProofPhotos do
  @moduledoc """
  Proof-photo handling for delivery attempts.

  Originals are stored unchanged under a configured persistent-volume root using
  a generated, non-user-controlled path. Only relative paths and metadata are
  persisted on the attempt. Admin photo views use short-lived signed imgproxy
  URLs; raw filesystem paths are never public.
  """
  @accept ~w(.jpg .jpeg .png .heic .webp)
  @max_size 20_000_000

  def accept, do: @accept
  def max_size, do: @max_size

  @doc """
  Stores an uploaded original and returns the attempt photo metadata. The path is
  generated server-side; the client filename only contributes a sanitised
  extension.
  """
  def store(tmp_path, entry) do
    relative_path = generate_relative_path(entry)

    case storage().put(tmp_path, relative_path) do
      :ok ->
        {:ok,
         %{
           photo_path: relative_path,
           photo_media_type: entry.client_type,
           photo_original_filename: entry.client_name,
           photo_byte_size: entry.client_size
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(nil), do: :ok
  def delete(relative_path), do: storage().delete(relative_path)

  @doc "Short-lived signed imgproxy URL for an authenticated admin photo view."
  def signed_url(relative_path) do
    Imgproxy.new("local:///#{relative_path}") |> to_string()
  end

  defp generate_relative_path(entry) do
    ext = entry.client_name |> Path.extname() |> String.downcase()
    ext = if ext in @accept, do: ext, else: ".jpg"
    "proof_photos/#{Ecto.UUID.generate()}#{ext}"
  end

  defp storage,
    do: Application.get_env(:edenflowers, :proof_photo_storage, Edenflowers.ProofPhotos.LocalStorage)
end
