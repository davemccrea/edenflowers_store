defmodule Edenflowers.External.PapraAPI.Behaviour do
  @moduledoc """
  Contract for fetching documents and managing their tags in Papra.
  """

  @callback fetch_document(organization_id :: String.t(), document_id :: String.t()) ::
              {:ok, %{body: binary(), content_type: String.t()}}
              | {:error, term()}

  @callback add_document_tag(document_id :: String.t(), tag_name :: String.t()) :: :ok | {:error, term()}

  @callback remove_document_tag(document_id :: String.t(), tag_name :: String.t()) :: :ok | {:error, term()}

  @callback rename_document(document_id :: String.t(), name :: String.t()) :: :ok | {:error, term()}
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

  def receipt_tag, do: "receipt"
  def processed_tag, do: "processed"

  @impl true
  def fetch_document(organization_id, document_id) do
    url =
      "#{base_url()}/api/organizations/#{organization_id}/documents/#{document_id}/file"

    case Req.get(url, auth: {:bearer, api_key()}, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %{body: body, content_type: "application/pdf"}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:papra_http_error, status}}

      {:error, reason} ->
        {:error, {:papra_request_failed, reason}}
    end
  end

  # Papra's API adds and removes tags by ID, so the name is looked up first.
  # The tag has to exist in Papra already.
  @impl true
  def add_document_tag(document_id, tag_name) do
    case find_tag_id(tag_name) do
      {:ok, nil} -> {:error, {:papra_tag_not_found, tag_name}}
      {:ok, tag_id} -> post_document_tag(document_id, tag_id)
      {:error, error} -> {:error, error}
    end
  end

  # A tag or document that no longer exists counts as already removed.
  @impl true
  def remove_document_tag(document_id, tag_name) do
    case find_tag_id(tag_name) do
      {:ok, nil} -> :ok
      {:ok, tag_id} -> delete_document_tag(document_id, tag_id)
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def rename_document(document_id, name) do
    url = "#{organization_api_url()}/documents/#{document_id}"

    case Req.patch([url: url, json: %{name: name}, auth: {:bearer, api_key()}] ++ req_options()) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:papra_http_error, status}}
      {:error, reason} -> {:error, {:papra_request_failed, reason}}
    end
  end

  defp find_tag_id(tag_name) do
    case Req.get([url: "#{organization_api_url()}/tags", auth: {:bearer, api_key()}] ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: %{"tags" => tags}}} ->
        {:ok, Enum.find_value(tags, fn tag -> tag["name"] == tag_name && tag["id"] end)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:papra_http_error, status}}

      {:error, reason} ->
        {:error, {:papra_request_failed, reason}}
    end
  end

  defp post_document_tag(document_id, tag_id) do
    url = "#{organization_api_url()}/documents/#{document_id}/tags"

    case Req.post([url: url, json: %{tagId: tag_id}, auth: {:bearer, api_key()}] ++ req_options()) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:papra_http_error, status}}
      {:error, reason} -> {:error, {:papra_request_failed, reason}}
    end
  end

  defp delete_document_tag(document_id, tag_id) do
    url = "#{organization_api_url()}/documents/#{document_id}/tags/#{tag_id}"

    case Req.delete([url: url, auth: {:bearer, api_key()}] ++ req_options()) do
      {:ok, %Req.Response{status: status}} when status in [204, 404] -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:papra_http_error, status}}
      {:error, reason} -> {:error, {:papra_request_failed, reason}}
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
