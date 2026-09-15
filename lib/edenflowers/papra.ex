defmodule Edenflowers.Papra.Behaviour do
  @callback fetch_document(organization_id :: String.t(), document_id :: String.t()) ::
              {:ok, %{body: binary(), content_type: String.t()}}
              | {:error, term()}
end

defmodule Edenflowers.Papra do
  @moduledoc """
  Thin client for the Papra document archiving API.

  Knows the base URL and API key (from config) and how to fetch a document's
  raw bytes. Used by `Edenflowers.Workers.ProcessExpenseDocument` after a
  `document:created` webhook arrives carrying only the document's ID.
  """

  @behaviour Edenflowers.Papra.Behaviour

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

  def document_url(document_id) do
    org_id = Application.get_env(:edenflowers, :papra_organization_id)
    "#{base_url()}/organizations/#{org_id}/documents/#{document_id}/pdf-viewer"
  end

  defp base_url, do: Application.get_env(:edenflowers, :papra_base_url)
  defp api_key, do: Application.get_env(:edenflowers, :papra_api_key)
end
