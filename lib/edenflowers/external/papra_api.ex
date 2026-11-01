defmodule Edenflowers.External.PapraAPI.Behaviour do
  @moduledoc """
  Contract for fetching, uploading and updating documents in Papra.
  """

  @callback fetch_document(organization_id :: String.t(), document_id :: String.t()) ::
              {:ok, %{body: binary(), content_type: String.t()}}
              | {:error, term()}

  @callback update_document(document_id :: String.t(), fields :: map()) :: :ok | {:error, term()}

  @callback upload_document(filename :: String.t(), body :: binary()) ::
              :ok | {:error, :already_exists} | {:error, term()}
end

defmodule Edenflowers.External.PapraAPI do
  @moduledoc """
  Thin client for the Papra document archiving API.

  Knows the base URL and API key (from config) and how to fetch a document's
  raw bytes. Used by `Edenflowers.Expenses.Changes.Process` after a
  `document:created` webhook arrives carrying only the document's ID.
  """

  @behaviour Edenflowers.External.PapraAPI.Behaviour

  @doc "The configured implementation: this module, or the mock in tests."
  def impl, do: Application.get_env(:edenflowers, :papra_api, __MODULE__)

  @impl true
  def fetch_document(organization_id, document_id) do
    url =
      "#{base_url()}/api/organizations/#{organization_id}/documents/#{document_id}/file"

    case Req.get([url: url, auth: {:bearer, api_key()}, decode_body: false] ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: body} = response} ->
        {:ok, %{body: body, content_type: content_type(body, response)}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:papra_http_error, status}}

      {:error, reason} ->
        {:error, {:papra_request_failed, reason}}
    end
  end

  # Papra serves a document with the type it was uploaded as, which can be wrong: our email import uploads
  # every attachment as a PDF, and anyone can drop a screenshot in. Claude rejects a mislabelled file,
  # so the bytes decide, and the header only covers types we don't recognise.
  defp content_type(<<"%PDF", _::binary>>, _response), do: "application/pdf"
  defp content_type(<<0x89, "PNG", _::binary>>, _response), do: "image/png"
  defp content_type(<<0xFF, 0xD8, 0xFF, _::binary>>, _response), do: "image/jpeg"
  defp content_type(<<"GIF8", _::binary>>, _response), do: "image/gif"
  defp content_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>, _response), do: "image/webp"

  defp content_type(_body, response) do
    case Req.Response.get_header(response, "content-type") do
      [type | _] -> type |> String.split(";") |> hd() |> String.trim()
      [] -> "application/pdf"
    end
  end

  # Papra accepts `name`, `documentDate` (ISO 8601), `content` and `notes`;
  # the public docs only list the first and third.
  @impl true
  def update_document(document_id, fields) do
    url = "#{organization_api_url()}/documents/#{document_id}"

    case Req.patch([url: url, json: fields, auth: {:bearer, api_key()}] ++ req_options()) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:papra_http_error, status}}
      {:error, reason} -> {:error, {:papra_request_failed, reason}}
    end
  end

  # Papra rejects a file whose bytes are already in the organization, without saying which document has them.
  @impl true
  def upload_document(filename, body) do
    file = {body, filename: filename, content_type: "application/pdf"}
    request = [url: "#{organization_api_url()}/documents", form_multipart: [file: file], auth: {:bearer, api_key()}]

    case Req.post(request ++ req_options()) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 409}} ->
        {:error, :already_exists}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:papra_http_error, status}}

      {:error, reason} ->
        {:error, {:papra_request_failed, reason}}
    end
  end

  def documents_url do
    org_id = Application.get_env(:edenflowers, :papra_organization_id)
    "#{base_url()}/organizations/#{org_id}/documents"
  end

  def document_url(document_id) do
    "#{documents_url()}/#{document_id}/pdf-viewer"
  end

  defp organization_api_url do
    "#{base_url()}/api/organizations/#{Application.get_env(:edenflowers, :papra_organization_id)}"
  end

  defp base_url, do: Application.get_env(:edenflowers, :papra_base_url)
  defp api_key, do: Application.get_env(:edenflowers, :papra_api_key)
  defp req_options, do: Application.get_env(:edenflowers, :papra_req_options, [])
end
